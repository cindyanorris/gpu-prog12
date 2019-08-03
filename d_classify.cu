#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <cuda_runtime.h>
#include "config.h"
#include "histogram.h"
#include "d_classify.h"
#include "CHECK.h"
#include "wrappers.h"

//parameters for building the histogram from the image
//TILEWIDTH is number of pixels in a row that a single thread will handle
#define TILEWIDTH 8 
#define HISTBLOCKDIM 32

//parameter is for classifying the image
#define CLASSBLOCKDIM 128

//prototypes for functions local to this file
static float histogramOnGPU(histogramT *, unsigned char *, int, int);
static float classifyOnGPU(float *, int *, int modelCt);

//prototypes for the kernels
static __global__ void d_histoKernel(histogramT *, unsigned char *, int, int, int);
static __global__ void d_classifyKernel(float *, float *, int *);
static __global__ void emptyKernel();

//prototypes of functions called by d_classifyKernel
static __device__ void computeHistSz(int *, int *);
static __device__ void normalizeHist(float *, int *, int);
static __device__ void intersection(float * normHistograms, float * intersect);

//for debugging
static __device__ void printFloatArray(float * array, int startIdx, int length);

/*
    d_classify
    Performs image classification on the GPU by first building a histogram
    to represent the image and then comparing the histogram to each of the
    histogram models.

    Outputs:
    Phisto - pointer to histogramT struct containing the bins 
    dresult - comparisonT array of structs; one element per model

    Inputs:
    models - an array of pointers to histogramT structs; one element per
             model to be compared to the input
    Pin - array contains the color pixels of the image to be used for 
          building a histogram and doing the classification
    width and height - dimensions of the image
 
    Returns the amount of time it takes to build the histogram and
      classify the image
*/
float d_classify(histogramT * Phisto, comparisonT * dresult, 
                 histogramT ** models, int modelCt, unsigned char * Pin,
                 int height, int width) 
{
    //THIS CODE IS COMPLETE

    float gpuMsecTime1, gpuMsecTime2;

    //launch an empty kernel to get more accurate timing
    emptyKernel<<<1024, 1024>>>();

    //build a histogram of the input image
    gpuMsecTime1 = histogramOnGPU(Phisto, Pin, height, width);

    //allocate array to hold all histograms, including the histogram for the input
    int * histograms = (int *) Malloc(sizeof(int) * (modelCt + 1) * TOTALBINS);

    //copy the histogram for the input to the beginning of the array
    memcpy(histograms, Phisto->histogram, sizeof(int) * TOTALBINS);

    //copy the remaining histograms
    for (int i = 1; i <= modelCt; i++) 
        memcpy(&histograms[i*TOTALBINS], models[i - 1]->histogram, sizeof(int) * TOTALBINS);

    //allocate an array of floats to hold the comparisons
    float * comparisons = (float *) Malloc(sizeof(int) * modelCt);

    //perform the classification
    gpuMsecTime2 = classifyOnGPU(comparisons, histograms, modelCt);

    //copy the results into the output
    for (int i = 0; i < modelCt; i++)
    {
        dresult[i].comparison = comparisons[i];
        strncpy(dresult[i].fileName, models[i]->fileName, NAMELEN);
    }

    return gpuMsecTime1 + gpuMsecTime2;
}

/*
   histogramOnGPU
   Builds a histogram to represent the input image.

   Outputs:
   Phisto - pointer to the histogramT struct containing the bins

   Inputs:
   Pin - array contains the color pixels of the image to be used for 
         building a histogram
   width and height -  dimensions of the image
   pitch - size of each row
 
   Returns the amount of time it takes to build the histogram 
*/
float histogramOnGPU(histogramT * Phisto, unsigned char * Pin, int height, 
                     int width)
{
    //THIS CODE IS COMPLETE

    cudaEvent_t start_gpu, stop_gpu;
    float gpuMsecTime = -1;

    unsigned char * d_Pin;
    int pitch;
    histogramT * d_Phisto;

    //create an array on the GPU to hold the pitched image
    CHECK(cudaMallocPitch((void **)&d_Pin, (size_t *) &pitch,
                          (size_t) (width * CHANNELS),
                          (size_t) height));
    for (int i = 0; i < height; i++)
       CHECK(cudaMemcpy(&d_Pin[i * pitch], &Pin[i * width * CHANNELS],
             width * CHANNELS, cudaMemcpyHostToDevice));

    //create the array on the GPU to hold the histogram
    CHECK(cudaMalloc((void **)&d_Phisto, sizeof(histogramT)));
    CHECK(cudaMemcpy(d_Phisto, Phisto, sizeof(histogramT),
          cudaMemcpyHostToDevice));

    //Use cuda functions to do the timing 
    //create event objects
    CHECK(cudaEventCreate(&start_gpu));
    CHECK(cudaEventCreate(&stop_gpu));
    
    //build the histogram
    CHECK(cudaEventRecord(start_gpu));

    //each thread calculates TILEWIDTH elements in a row
    dim3 grid(ceil(width/(float)(HISTBLOCKDIM * TILEWIDTH)),
              ceil(height/(float)HISTBLOCKDIM), 1);
    dim3 block(HISTBLOCKDIM, HISTBLOCKDIM, 1);

    d_histoKernel<<<grid, block>>>(d_Phisto, d_Pin, height, width, pitch);

    CHECK(cudaEventRecord(stop_gpu));
    CHECK(cudaMemcpy(Phisto, d_Phisto, sizeof(histogramT),
          cudaMemcpyDeviceToHost));
    //record the ending time and wait for event to complete
    CHECK(cudaEventSynchronize(stop_gpu));
    //calculate the elapsed time between the two events 
    CHECK(cudaEventElapsedTime(&gpuMsecTime, start_gpu, stop_gpu));
    //CHECK(cudaEventDestroy(start_gpu));
    //CHECK(cudaEventDestroy(stop_gpu));

    return gpuMsecTime;
}

/*
   d_histoKernel
   Kernel code executed by each thread on its own data when the kernel is
   launched. Each thread operates on TILEWIDTH pixels in a row.

   Inputs:
   Pin - array contains the color pixels to be used to build the histogram
   width and height - dimensions of the image
   pitch - size of each row

   Output:
   histo - pointer to a histogramT struct that contains an array of bins
*/
__global__
void d_histoKernel(histogramT * histo, unsigned char * Pin, int height,
                  int width, int pitch)
{
    //THIS CODE IS COMPLETE.  You can replace it with a faster version
    //if you like, but the shared memory version won't work with all
    //TOTALBINS sizes.  If you use that one, the largest BIN value can
    //only be 8.

    int colStart = (blockIdx.x * blockDim.x + threadIdx.x) * TILEWIDTH;
    int row = blockIdx.y * blockDim.y + threadIdx.y;
    int col;

    //use a privatization technique to reduce the number of atomic adds
    int accumulator = 0;
    int prevBin = -1;
    int currBin;

    //go through each pixel in the tile
    for (int i = 0; i < TILEWIDTH; i++)
    {
        col = colStart + i;
        if (row < height && col < width)
        {
            //flatten the 2D indices
            int pIndx = row * pitch + col * CHANNELS;

            unsigned char redVal = Pin[pIndx];
            unsigned char greenVal = Pin[pIndx + 1];
            unsigned char blueVal = Pin[pIndx + 2];
            currBin = (redVal/TONESPB)*BINS*BINS + (blueVal/TONESPB)*BINS
                       + greenVal/TONESPB;
            if (currBin != prevBin)
            {
                if (accumulator > 0) 
                    atomicAdd(&(histo->histogram[prevBin]), accumulator); 
                prevBin = currBin;
                accumulator = 1;
            } else accumulator++;
        }
    }
    if (accumulator > 0)
    {
        atomicAdd(&(histo->histogram[prevBin]), accumulator); 
    }
}

/*
    classifyOnGPU
    Performs image classification on the GPU

    Outputs:
    comparisons - an array of size modelCt. comparisons[i] is set to the
                  result of comparing the input image to model i
                  The size of this array is modelCt.

    Inputs:
    histograms - an array of histograms. 
        The histogram for the input image is in:
        histograms[0] ... histogram[TOTALBINS - 1]
        The histogram for model 0 is in:
        histograms[TOTALBINS] ... histogram[2*TOTALBINS - 1]

        The histogram for the last model is in:
        histograms[modelCt*TOTALBINS] ... histogram[modelCt*TOTALBINS - 1]
        Thus, note that the array contains the input histogram and the
        model histograms and thus is of size (modelCt + 1) * TOTALBINS
   
    modelCt - count of the number of models used for the classification 
 
    Returns the amount of time it takes to classify the image
*/
float classifyOnGPU(float * comparisons, int * histograms, int modelCt)
{
    cudaEvent_t start_gpu, stop_gpu;
    float gpuMsecTime = -1;

    //THIS FUNCTION IS NOT COMPLETE.  You need to:
    //1) allocate a float array on the GPU to hold the normalized histograms
    //It needs to be big enough to hold the histogram of the input image and
    //and the histograms of all of the models.
    float * normHistograms;

    //2) allocate an int array on the GPU to hold the original histograms
    //It needs to be big enough to hold the histogram of the input image and
    //and the histograms of all of the models.
    int * dhistograms;

    //3) copy input histograms into dhistograms
 
    //4) allocate a float array on the GPU to hold the comparisons
    //there needs to be one element per model
    float * dcomparisons;


    //THE REST OF THIS FUNCTION IS COMPLETE 
    //Use cuda functions to do the timing 
    //create event objects
    CHECK(cudaEventCreate(&start_gpu));
    CHECK(cudaEventCreate(&stop_gpu));

    //record the starting time
    CHECK(cudaEventRecord(start_gpu));

    //each model is handled by a single block of threads
    //an extra block of threads is needed to normalize the input histogram
    dim3 grid(modelCt + 1, 1, 1);
    //don't make block any larger than the number of bins
    dim3 block(min(TOTALBINS, CLASSBLOCKDIM), 1);

    d_classifyKernel<<<grid, block>>>(dcomparisons, normHistograms, dhistograms);

    CHECK(cudaEventRecord(stop_gpu));

    //copy the device comparison array into the host comparison array
    CHECK(cudaMemcpy(comparisons, dcomparisons, sizeof(float) * modelCt,
          cudaMemcpyDeviceToHost));

    //record the ending time and wait for event to complete
    CHECK(cudaEventSynchronize(stop_gpu));
    //calculate the elapsed time between the two events 
    CHECK(cudaEventElapsedTime(&gpuMsecTime, start_gpu, stop_gpu));

    return gpuMsecTime;
}

/*
    d_classifyKernel
    Kernel used to do the image classification on the GPU.  Each block of
    threads normalizes a single histogram. After that, every block except
    for block 0 will perform the intersection and store a
    result in the comparisons array.
    Thus, each block (except for 0) produces one result for the comparisons
    array.  Each thread in a block handles TOTALBINS/blockDim.x elements
 
    Inputs: 
    histograms - array of size gridDim.x * TOTALBINS. It contains
                 gridDim.x histograms each of size TOTALBINS.  The first one 
                 is the input histogram.
    Outputs:
    comparisons - comparison[i] is set to the value of the comparison of the
                  input histogram and the histogram of model i; for example,
                  comparison[0] is set to comparison of the input and model 0.
    normHistograms - array of size gridDim.x * TOTALBINS.  It contains
                     gridDim.x histograms that are equal to the normalization
                     of the input histograms.
*/

__device__ int blockSync = 0;   //need this to provide synchronization among blocks
__global__ void d_classifyKernel(float * comparisons, float * normHistograms, int * histograms) 
{
    __shared__ int histSz;
    __shared__ float intersect;

    //The device functions (that need to be written) are below this function

    //1) initialize histSz and intersect to 0

    //2) compute the size of the histogram handled by this block

    //3) normalize the histogram 

    //4) after block 0 has finished computing the normalized histogram,
    //one thread in its block should set blockSync to 1 so other blocks can
    //then proceed to compute the intersection

    //5) if not a block 0 thread, wait until blockSync is no longer 0 before 
    //continuing (page 193 has logic similar to what has to be done here)

    //6) compute the intersection

    //7) one thread in all blocks except 0 should store the fractional intersect
    //value in the comparisons array
}


/* 
    intersection
    Calculates the intersection of the input histogram and a model histogram
    after they have been normalized.
    The input histogram is in normHistograms[0] ... normHistograms[TOTALBINS - 1]
    The model histogram is in normHistograms[TOTALBINS * blockIdx.x] ...
    normHistograms[TOTALBINS * (blockIdx.x + 1) - 1]
   
    Inputs:
    normHistograms - array of TOTALBINS * gridDim.x bins (gridDim.x histograms)
    intersect - pointer to the shared intersect value

    Outputs:
    shared intersect variable is incremented by the intersection calculated by the
       thread running this code 
*/
__device__ void intersection(float * normHistograms, float * intersect)
{
    //compute intersection using cyclic partitioning

}

/*
    computeHistSz
    Calculates the size of a histogram by adding up all of the bin
    values. The histogram to be used for the calculation is in elements
    histograms[blockIdx.x * TOTALBINS] ... histograms[(blockIdx.x + 1) * TOTALBINS - 1]
  
    Inputs:
    histograms - array of TOTALBINS * gridDim.x bins (gridDim.x histograms)
    histSz - pointer to the shared histogram size variable

    Outputs:
    shared histogram size variable is incremented by the size calculated by
         the thread running this code
*/
__device__ void computeHistSz(int * histograms, int * histSz)
{
    //compute histogram size (sum of bins) using cyclic partitioning

}

/*
    normalizeHist
    Normalizes the histogram so that every bin value is between 0 and NORMMAX.
    The histogram to be normalized is in elements
    histograms[blockIdx.x * TOTALBINS] ... histograms[(blockIdx.x + 1) * TOTALBINS - 1]
    The result will be stored in normHistograms[blockIdx.x * TOTALBINS] ... 
    normHistograms[(blockIdx.x + 1) * TOTALBINS - 1]

    Inputs:
    histograms - array that holds the histogram to be normalized
    histSz - size of the input histogram (sum of its bins)

    Outputs:
    normHistograms - array to hold the normalized histogram
*/
__device__ void normalizeHist(float * normHistograms, int * histograms, int histSz)
{
    //compute the normalized histogram using cyclic partitioning

} 

//this can be used for debugging
__device__ void printFloatArray(float * array, int startIdx, int length)
{
    int i, j = 0;
    for (i = startIdx; i < startIdx + length; i++, j++)
    {
        if ((j % 16) == 0) printf("\n%3d: ", i);
        printf("%6.1f ", array[i]);
    } 
}        

//launched to get more accurate timing
__global__ void emptyKernel()
{
}
