//structure to hold the name of the file containing the
//image that was histogrammed and the histogram itself, which is
//an int array of bins
typedef struct
{
    char fileName[NAMELEN];
    int histogram[TOTALBINS];
} histogramT;

//structure to hold the name of the file containing the
//image whose histogram was compared to the input image's
//histogram and the result of the comparison
typedef struct
{
    char fileName[NAMELEN];
    float comparison;
} comparisonT;


