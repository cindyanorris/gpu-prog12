#include <stdio.h>
#include "config.h"
#include "histogram.h"
#include "h_classify.h"
#include "CHECK.h"
#include "wrappers.h"

static void classifyOnCPU(histogramT **, int, histogramT *, comparisonT *); 
static void normalizeHistogram(float *, histogramT *, int);
static float computeIntersection(float *, float *, int);
static int sumInts(int *, int);
static void printFloatArray(float * array, int startIdx, int length);

/*
   h_classify
   Builds a histogram of an input image and classifies the
   histogram using the provided models.

   Outputs:
   Phisto - pointer to a histogram structure that will be set
            to the histogram built
   results - an array of structs where each struct contains the name of
             the model used to compute the comparison and the comparison result

   Inputs:
   models - an array of histograms that is used to perform the classification
   modelCt - count of the number of models
   Pin - array that contains the color pixels.
   width and height - dimensions of the image.
*/
float h_classify(histogramT * Phisto, comparisonT * results,
                 histogramT ** models, int modelCt, unsigned char * Pin, 
                 int height, int width) 
{
    cudaEvent_t start_cpu, stop_cpu;
    float cpuMsecTime = -1;

    //Use cuda functions to do the timing 
    //create event objects
    CHECK(cudaEventCreate(&start_cpu));
    CHECK(cudaEventCreate(&stop_cpu));

    //record the starting time
    CHECK(cudaEventRecord(start_cpu));

    //first calculate histogram
    histoOnCPU(Phisto, Pin, height, width);

    //now, classify it
    classifyOnCPU(models, modelCt, Phisto, results);
 
    //record the ending time and wait for event to complete
    CHECK(cudaEventRecord(stop_cpu));
    CHECK(cudaEventSynchronize(stop_cpu));
    //calculate the elapsed time between the two events 
    CHECK(cudaEventElapsedTime(&cpuMsecTime, start_cpu, stop_cpu));
    CHECK(cudaEventDestroy(start_cpu));
    CHECK(cudaEventDestroy(stop_cpu));
    return cpuMsecTime;
}

/*
   histoOnCPU
   Performs the histo of an image on the CPU.

   Output:
   Phisto - pointer to a histogram structure that will be set
            to the histogram built
   Inputs:
   Pin - array that contains the color pixels.
   width and height - dimensions of the image.
*/
void histoOnCPU(histogramT * Phisto, unsigned char * Pin, int height, 
               int width)
{
    unsigned char redVal, greenVal, blueVal;
    int j, i; 

    //calculate the row width of the input 
    int rowWidth = CHANNELS * width;
    for (j = 0; j < height; j++)
    {
        for (i = 0; i < width; i++)
        {
            //use red, green, and blue values to compute bin number
            redVal = Pin[j * rowWidth + i * CHANNELS]; 
            greenVal = Pin[j * rowWidth + i * CHANNELS + 1]; 
            blueVal = Pin[j * rowWidth + i * CHANNELS + 2]; 
            int bin = (redVal/TONESPB)*BINS*BINS + (blueVal/TONESPB)*BINS
                      + greenVal/TONESPB;
            Phisto->histogram[bin]++; 
        }
    }
}

/* 
    classifyOnCPU   
    Takes as input a histogram and array of model histograms and compares the input
    histogram to each model by calculating an intersection. The result of each
    comparison and the name of the model is stored in the results array.

    Inputs:
    models - array of histograms to use for the comparison
    input - input histogram to be compared to the others
    Outputs:
    results - result of the comparisons
*/ 
void classifyOnCPU(histogramT ** models, int modelCt, histogramT * input, 
                   comparisonT * results)
{
    int i = 0;

    float intersection;
    float * normInput = (float *) Malloc(sizeof(float) * TOTALBINS);
    float * normModel = (float *) Malloc(sizeof(float) * TOTALBINS);

    //since images may be different sizes, their histograms need to be normalized
    //to a common size
    //first, normalize the input histogram
    normalizeHistogram(normInput, input, TOTALBINS);
    for (i = 0; i < modelCt; i++)
    {
        //normalize the model used in the comparison
        normalizeHistogram(normModel, models[i], TOTALBINS); 

        //compare normalized input to normalized model
        intersection = computeIntersection(normInput, normModel, TOTALBINS);

        //calculate and store the result of the comparison
        results[i].comparison = intersection/NORMMAX;
        strcpy(results[i].fileName, models[i]->fileName);
    }
}

/*
    computeIntersection
    This function returns the intersection of the two histograms. 
    If a pixel is in an intersection then the pixel appears in both the
    images.

    Inputs:
    model - histogram to use for intersection
    input - histogram to use for intersection
    numBins - number of bins in each histogram array
    Outputs:
    returns intersection
*/
float computeIntersection(float * model, float * input, int numBins)
{
    float result = 0;
    int i;
    for (i = 0; i < numBins; i++)
    {
        //For example, RGB i appears Y times in input and Z times in model
        //and therefore at least min(Y,Z) times in each
        result += min(input[i], model[i]);
    }
    return result; 
}

/*
   sumInts
   Returns the sum of an array of ints.

   Inputs:
   array - pointer to an array of ints
   length - length of an array
   Output:
   sum of array
*/
int sumInts(int * array, int length)
{
    int sum = 0;
    int i;
    for (i = 0; i < length; i++) sum += array[i];
    return sum;
}

/*
    normalizeHistograms
    This function produces an output array of floats that is the normalization
    of the data in the input array. If the range of input bin values
    is from 0 to MAX then the bin values in the output array will range from
    0 to NORMMAX. 
    Inputs:
    input - pointer to a struct containing the histogram bins 
    length - number of bins in the histogram
    Output:
    normData - normalization of the output data
*/
void normalizeHistogram(float * normData, histogramT * input, int length)
{
    //get the count of the number of pixels in the histogram
    //by adding up all of the bins
    int pixels = sumInts(input->histogram, TOTALBINS);
    int i;
    for (i = 0; i < length; i++)
    {
        normData[i] = (input->histogram[i]/(float)pixels) * NORMMAX;
    }
}

//can be used for debugging
void printFloatArray(float * array, int startIdx, int length)
{
    int i, j = 0;
    for (i = startIdx; i < startIdx + length; i++, j++)
    {
        if ((j % 16) == 0) printf("\n%3d: ", i);
        printf("%6.1f ", array[i]);
    }
    printf("\n");
}

