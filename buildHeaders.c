#include <sys/stat.h>
#include <dirent.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <jpeglib.h>
#include <jerror.h>
//config.h contains a number of needed definitions
#include "config.h"  
#include "histogram.h"

//prototypes for functions in this file 
static void parseCommandArgs(int, char **, char *, char *);
static void buildAllHeaders(char *, char *);
static void buildOneHeader(char *, char *);
static void printUsage();
static int isImage(char * filename);
static void buildHistogram(histogramT *, unsigned char *, int, int);
static void initHistogram(char *, histogramT *, int);
static void readJPGImage(char *, unsigned char **, int *, int *);
static void buildName(const char * , char name[NAMELEN]);
static void writeHistogram(histogramT *, char *);
static void writeBin(FILE *, int *, int);

//Build a file named models.h that contains includes
//for all of the headers built by this program
const char * outputHeader = "models.h";
FILE * outputHeaderFP;
int modelCount = 0;
char modelList[MAXMODELS][NAMELEN];

/*
    main 
    Takes as input the name of a directory containing images and
    the name of the directory that will be used to hold header files.
    A header file is created for each image that contains a histogram
    representation of the image.  Thus, this program creates a
    histogram for each image in the images directory.
    In addition, it creates a models.h file that contains includes
    for each header file.
*/
int main(int argc, char * argv[])
{
    char headersDir[NAMELEN];
    char imagesDir[NAMELEN];

    outputHeaderFP = fopen(outputHeader, "w");
    if (outputHeaderFP == NULL)
    {
        printf("\nUnable to open output file: %s\n", outputHeader);
        printUsage();
    }

    parseCommandArgs(argc, argv, imagesDir, headersDir);
    buildAllHeaders(imagesDir, headersDir);

    //finish up the output to the models.h file
    fprintf(outputHeaderFP, "\n#define MODELS %d\n\n", modelCount);
    fprintf(outputHeaderFP, "histogramT * models[MODELS] = {");
    for (int i = 0; i < modelCount - 1; i++)
    {
        if (i % 5 == 0) fprintf(outputHeaderFP, "\n");
        fprintf(outputHeaderFP, "&%s, ", (char *) modelList[i]);
    }
    fprintf(outputHeaderFP, "&%s};\n", (char *) modelList[modelCount - 1]);
    fclose(outputHeaderFP);

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
    writeHistogram
    Writes a histogram to an output file.

*/
void writeHistogram(histogramT * histP, char * headersDir)
{
    char varname[NAMELEN];
    char outfile[NAMELEN];
    buildName(histP->fileName, varname);
    strcpy(outfile, headersDir);
    strcpy(&outfile[strlen(outfile)], "/");
    strcpy(&outfile[strlen(outfile)], varname);
    strcpy(&outfile[strlen(outfile)], ".h");
    fprintf(outputHeaderFP, "#include \"%s\"\n", outfile);
    strcpy(modelList[modelCount], varname);
    modelCount++;
    FILE *fp = fopen(outfile, "w");
    if (fp == NULL)
    {
        printf("\nUnable to open output file: %s\n", outfile);
        printUsage();
    }
    fprintf(fp, "histogramT %s =\n{\n\"%s.jpg\",\n", varname, varname);
    writeBin(fp, histP->histogram, TOTALBINS);
    fprintf(fp, "\n};");
    fclose(fp);
}

/*
   buildName
   Used to strip off the final four characters (.jpg) in a file
   name and any leading characters up to and including the
   last / to build a name that is then stored in the output file
   with the histogram.

   example: buildName("images/CaptainAmerica1.jpg", varname)
            stores "CaptainAmerica1" in varname
*/ 
void buildName(const char * outfile, char varname[NAMELEN])
{
    int endPoint = strlen(outfile) - 4;
    int startPoint = endPoint;
    //decrement startPoint until it reaches beginning of string
    //or a /
    while (startPoint > 0)
    {
        if (outfile[startPoint] == '/') {startPoint++; break;}
        startPoint--;
    }
    strcpy(varname, &outfile[startPoint]);
    varname[strlen(varname)-4] = '\0';
    
}

/*
   writeBin
   Outputs the bin to the output file.
*/
void writeBin(FILE * fp, int * bin, int length)
{
   int i;
   fprintf(fp, "{\n");
   for (i = 0; i < length - 1; i++)
   {
        fprintf(fp, "%d, ", bin[i]);
        if ((i + 1) % 32 == 0) fprintf(fp, " /* %d-%d */\n", i - 31, i);
   }
   fprintf(fp, "%d /* %d-%d */\n}", bin[i], i - 31, i);
}

/*
    readJPGImage
    This function opens a jpg file and reads the contents.  
    
    The array Pin is initialized to the pixel bytes.  width and height
    are pointers to ints that are set to those values.
    filename - name of the .jpg file
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
   
   printf("Building header for: %s\n", filename);
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
    directoryExists
    Takes as input a C-string that contains a directory path
    and returns 1 if the directory exists and 0 otherwise.
*/
int directoryExists(const char *path)
{
    struct stat stats;

    // Check for file existence
    if (stat(path, &stats) == 0 && S_ISDIR(stats.st_mode))
        return 1;

    return 0;
}

/*
    parseCommandArgs
    This function parses the command line arguments. The program should be 
    executed like this:
    ./buildHeaders -i <imagesdir> -h <headersdir>
*/
void parseCommandArgs(int argc, char * argv[], char imagesDir[NAMELEN],
                      char headersDir[NAMELEN])
{
    int fileIdx = argc - 1;
    struct stat buffer;

    if (argc < 3) printUsage();

    for (int i = 1; i < argc - 1; i+=2)
    {
        
        if (strncmp("-i", argv[i], 3) == 0) 
        {
            if (i+1 >= argc) printUsage();
            strncpy(imagesDir, argv[i+1], NAMELEN);
            if (!directoryExists(imagesDir)) 
            {
               printf("images directory %s does not exist\n", imagesDir);
               printUsage();
            }
        }
        else if (strncmp("-h", argv[i], 3) == 0) 
        {
            if (i+1 >= argc) printUsage();
            strncpy(headersDir, argv[i+1], NAMELEN);
            if (!directoryExists(headersDir)) 
            {
               printf("headers directory %s does not exist\n", headersDir);
               printUsage();
            }
        } else  
            printUsage();
    } 
}

/*
    isImage
    This function takes as input a string that is the name of a file and
    returns 1 if the filename ends with a .jpg and 0 otherwise.
*/
int isImage(char * filename)
{
    int len = strlen(filename);
    if (len < 5) return 0;
    return !(strcmp(".jpg", &filename[len - 4]));
}

/* 
    buildOneHeader
    This function takes as input the name of a directory to which
    the header should be stored and the path to an image file.
    It opens the image file, reads its contents, and creates
    a histogram struct that contains the histogram representation
    of the image file.  Then it writes that histogram representation
    to a header file.
*/
void buildOneHeader(char * headersDir, char * imageFile)
{
    unsigned char * Pin;
    int width, height;
    histogramT * hgram;
    hgram = (histogramT *) malloc(sizeof(histogramT));
    if (hgram == NULL) fprintf(stderr, "Fatal error: malloc failed\n");
    initHistogram(imageFile, hgram, TOTALBINS);
    readJPGImage(imageFile, &Pin, &width, &height);
    buildHistogram(hgram, Pin, height, width);
    writeHistogram(hgram, headersDir);
}

/*  
    buildHeaders
    This function takes as input the name of a directory containing
    jpeg images and the name of a directory in which header files
    are to be stored.  One header file is created for each jpeg
    image.  It contains a histogram representation of the image.
*/
void buildAllHeaders(char * imagesDir, char * headersDir)
{
    char fullPath[NAMELEN];
    DIR *d;
    struct dirent *dir;
    d = opendir(imagesDir);
    if (d)
    {
        while ((dir = readdir(d)) != NULL)
        {
            if (isImage(dir->d_name)) 
            {
                strcpy(fullPath, imagesDir);
                strcpy(&fullPath[strlen(fullPath)], "/");
                strcpy(&fullPath[strlen(fullPath)], dir->d_name);
                buildOneHeader(headersDir, fullPath);
            }
        }
        closedir(d);
    }
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
    printf("This application takes as input the name of a directory\n");
    printf("containing jpg images and the name of a directory where headers\n");
    printf("are to be stored. It computes a histogram of each image\n");
    printf("in the images directory and creates a header (.h) file\n");
    printf("to represent the histogram. The header file is then\n");
    printf("stored in the headers directory. In addition, the application\n");
    printf("builds a header file, models.h, that includes the header files\n");
    printf("built for each image.\n");
    printf("\nusage: ./buildHeaders -i <imagesdir> -h <headersdir> \n");
    printf("Examples:\n");
    printf("./buildHeaders -i images -h headers\n");
    exit(EXIT_FAILURE);
}

/*
    buildHistogram
    This function takes as input an array of pixels of an image and creates
    a histogram representation of that image.
    That histogram is stored in a histogram struct.
    Phisto - pointer to a histogram struct
    Pin - array of pixels
    height - height of image
    width of image
*/
void buildHistogram(histogramT * Phisto, unsigned char * Pin, 
                    int height, int width)
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

