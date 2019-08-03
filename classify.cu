#include <sys/stat.h>
#include <stdlib.h>
#include <stdio.h>
#include <jpeglib.h>
#include <jerror.h>
//config.h contains a number of needed definitions
#include "config.h"  
#include "histogram.h"
#include "wrappers.h"
#include "h_classify.h"
#include "d_classify.h"

#include "models.h"

//prototypes for functions in this file 
static void parseCommandArgs(int, char **, char *);
static void printUsage();
static void readJPGImage(char *, unsigned char **, int *, int *);
static void compareHistograms(histogramT *, histogramT *, int);
static void compareComparisons(comparisonT *, comparisonT *, int);
static void initHistogram(char *, histogramT *, int);
static void printTopTwo(comparisonT *);

/*
    main 
    Opens the jpg file and reads the contents.  Uses the CPU
    to build a histogram of the image, optionally outputting
    the histogram to a file in the form of a C struct initialization.  
    If the save option is not provided the program will also classify
    the image on the CPU and histogram and classify the image on the GPU.
    It compares the CPU and GPU results to make sure they match
    and outputs the times it takes on the CPU and the GPU to build the 
    histogram and perform the classification.
*/
int main(int argc, char * argv[])
{
    unsigned char * hPin, *dPin; 
    histogramT * h_hgram, * d_hgram;
    char imagefile[NAMELEN];
    int width, height;
    float cpuTime, gpuTime;

    //need an array of these; one for each model
    //one array for the GPU and one array for the CPU
    comparisonT * hresult = (comparisonT *) Malloc(sizeof(comparisonT) * MODELS);
    comparisonT * dresult = (comparisonT *) Malloc(sizeof(comparisonT) * MODELS);

    parseCommandArgs(argc, argv, imagefile);

    //create histogram structs for the host and the device
    h_hgram = (histogramT *) Malloc(sizeof(histogramT));
    d_hgram = (histogramT *) Malloc(sizeof(histogramT));
    initHistogram(imagefile, h_hgram, TOTALBINS);


    //read the image for the CPU
    readJPGImage(imagefile, &hPin, &width, &height);
    printf("\nComputing histogram and classifying %s.\n", imagefile);

    //use the CPU to build the histogram and classify it
    cpuTime = h_classify(h_hgram, hresult, models, MODELS, hPin, height, width); 
    printf("\tCPU time: \t\t%f msec\n", cpuTime);

    //read the image for the GPU
    readJPGImage(imagefile, &dPin, &width, &height);

    //use the GPU to build the histogram and classify it
    initHistogram(imagefile, d_hgram, TOTALBINS);
    gpuTime = d_classify(d_hgram, dresult, models, MODELS, dPin, height, width);
    compareHistograms(d_hgram, h_hgram, TOTALBINS);
    compareComparisons(dresult, hresult, MODELS);
    printf("\tGPU time: \t\t%f msec\n", gpuTime);
    printf("\tSpeedup: \t\t%f\n", cpuTime/gpuTime);
    printTopTwo(dresult);

    free(d_hgram);
    free(h_hgram);
    free(hPin);
    free(dPin);
    return EXIT_SUCCESS;
}

/*
    initHistogram
    Initializes a histogram struct by setting the bin values to 0 and setting
    the fileName field to the name of the file containing the image to histogram.
*/
void initHistogram(char * fileName, histogramT * histP, int length)
{
    int i;
    strncpy(histP->fileName, fileName, sizeof(histP->fileName));
    for (i = 0; i < length; i++)
    {
       histP->histogram[i] = 0;
    }
}

/*
    printTopTwo
    Finds and prints the top two matches in the comparison struct.
    comparison values will range from 0 to 1.
    An exact match will have a comparison value of 1.0, which indicates
    the model matches the input image exactly.  
    A comparison value of .8 means that %80 of the pixels in the
    model and the input image are the same.
*/
   
void printTopTwo(comparisonT * result)
{
    int first = -1, second = -1;
    int i;
    for (i = 0; i < MODELS; i++)
    {
        if (first == -1)  //both first and second are -1
            first = i;
        else if (second == -1) //first is not -1
        {
            if (result[i].comparison > result[first].comparison)
            {
                second = first;
                first = i;
            } else
            {
                second = i;
            }
        } else if (result[i].comparison > result[first].comparison)
        {
            second = first;
            first = i;
        } else if (result[i].comparison > result[second].comparison)
        {
            second = i;
        }
    }
    printf("\nMatches\n");
    printf("-------\n");
    printf("\tFirst:  %s    \t%5.1f%%\n", result[first].fileName, 
           (result[first].comparison * 100));
    printf("\tSecond: %s    \t%5.1f%%\n", result[second].fileName, 
           (result[second].comparison * 100));
}

/* 
    compareHistograms
    This function takes two histogramT structs. One histogramT 
    contains bins calculated  by the GPU. The other histogramT
    contains bins calculated by the CPU. This function examines
    each bin to see that they match.

    d_Pout - histogram calculated by GPU
    h_Pout - histogram calculated by CPU
    length - number of bins in histogram
    
    Outputs an error message and exits program if the histograms differ.
*/
void compareHistograms(histogramT * d_Pout, histogramT * h_Pout, int length)
{
    int i;
    for (i = 0; i < length; i++)
    {
        if (d_Pout->histogram[i] != h_Pout->histogram[i])
        {
            printf("Histograms don't match.\n");
            printf("host bin[%d] = %d\n", i, h_Pout->histogram[i]);
            printf("device bin[%d] = %d\n", i, d_Pout->histogram[i]);
            exit(EXIT_FAILURE);
        }
    }
}

/* 
    compareComparisons
    This function takes two comparisonT structs. One comparisonT 
    contains a comparison array calculated  by the GPU.  The other 
    comparsionT contains a comparison array calculated
    by the CPU.  This function examines each comparison array
    element to see that they match.

    d_Pout - comparison calculated by GPU
    h_Pout - comparison calculated by CPU
    length - number of comparison
    
    Outputs an error message and exits program if the comparisons differ.
*/
void compareComparisons(comparisonT * d_Pout, comparisonT * h_Pout, int length)
{
    int i;
    for (i = 0; i < length; i++)
    {
        if (abs(d_Pout[i].comparison - h_Pout[i].comparison) > 0.01)
        {
            printf("Comparisons don't match for %s.\n", d_Pout[i].fileName);
            printf("host comparison[%d] = %f\n", i, h_Pout[i].comparison);
            printf("device comparison[%d] = %f\n", i, d_Pout[i].comparison);
            exit(EXIT_FAILURE);
        }
    }
}

/*
    readJPGImage
    This function opens a jpg file and reads the contents.  
    
    The array Pin is initialized to the pixel bytes.  width and height
    are pointers to ints that are set to those values.
    filename is the name of the .jpg file
*/
void readJPGImage(char * filename, unsigned char ** Pin,
                  int * width, int * height)
{
   unsigned long dataSize;             // length of the file
   int channels;                       //  3 =>RGB   4 =>RGBA 
   unsigned char * rowptr[1];          // pointer to an array
   unsigned char * jdata;              // data for the image
   struct jpeg_decompress_struct info; //for our jpeg info
   struct jpeg_error_mgr err;          //the error handler

   FILE * fp = fopen(filename, "rb"); //read binary
   if (fp == NULL)
   {
      fprintf(stderr, "Error reading file %s\n", filename);
      printUsage();
   }

   info.err = jpeg_std_error(& err);
   jpeg_create_decompress(&info);

   jpeg_stdio_src(&info, fp);
   jpeg_read_header(&info, TRUE);   // read jpeg file header
   jpeg_start_decompress(&info);    // decompress the file
   //set width and height
   (*width) = info.output_width;
   (*height) = info.output_height;
   channels = info.num_components;
   if (channels != CHANNELS)
   {
      fprintf(stderr, "%s is not an RGB jpeg image\n", filename);
      printUsage();
   }

   dataSize = (*width) * (*height) * channels;
   jdata = (unsigned char *)malloc(dataSize);
   if (jdata == NULL) fprintf(stderr, "Fatal error: malloc failed\n");
   while (info.output_scanline < info.output_height) // loop
   {
      // Enable jpeg_read_scanlines() to fill our jdata array
      rowptr[0] = (unsigned char *)jdata +  // secret to method
                  channels * info.output_width * info.output_scanline;

      jpeg_read_scanlines(&info, rowptr, 1);
   }
   jpeg_finish_decompress(&info);   //finish decompressing
   jpeg_destroy_decompress(&info);
   fclose(fp);                      //close the file
   (*Pin) = jdata;
   return;
}


/*
    parseCommandArgs
    This function parses the command line arguments. The program is executed 
    like this:
    ./classify <file>.jpg
    In addition, it checks to see if the last command line argument
    is a jpg file and sets imageFile to argv[1] when argv[1] is the name of the jpg
    file.  
*/
void parseCommandArgs(int argc, char * argv[], char imageFile[NAMELEN])
{
    struct stat buffer;
    if (argc < 2 || strncmp("-h", argv[1], 3) == 0) 
    {
        printUsage();
    } 

    //check the input file name (must end with .jpg)
    int len = strlen(argv[1]);
    if (len < 5) printUsage();
    if (strncmp(".jpg", &argv[1][len - 4], 4) != 0) printUsage();

    //stat function returns 1 if file does not exist
    if (stat(argv[1], &buffer)) printUsage();
    strcpy(imageFile, argv[1]);
}

/*
    printUsage
    This function is called if there is an error in the command line
    arguments or if the .jpg file that is provided by the command line
    argument is improperly formatted.  It prints usage information and
    exits.
*/
void printUsage()
{
    printf("This application takes as input the name of a .jpg\n");
    printf("file containing a color image and creates a histogram\n");
    printf("of the image. It then computes an intersection of this histogram\n");
    printf("and the other histograms defined in 'models.h'. It outputs the\n");
    printf("names of the two best matching images. This work is\n");
    printf("performed on the CPU and the GPU. Their results are timed and\n");
    printf("compared.\n");
    printf("\nusage: ./classify <name>.jpg\n");
    printf("       <name>.jpg is the name of the input jpg file.\n");
    printf("Examples:\n");
    printf("./classify images/WonderWoman1.jpg\n");
    exit(EXIT_FAILURE);
}
