#define CHANNELS 3   //red, green blue
#define TONES 256    //colors are values between 0 and 255

//number of bins in one dimension of the three dimensions; space is 3D
//red bins by green bins by blue bins
//Can change this to 16 to get more bins (bigger than 16 causes precision failures)
#define BINS 8  

//tones per bin 
#define TONESPB (TONES/BINS)

//total number of bins as one dimension
#define TOTALBINS (BINS*BINS*BINS)

//since the images being compared may be different sizes
//they will need to be normalized
#define NORMMAX 2000

#define NAMELEN 80    //length of filenames
#define MAXMODELS 100 //maximum number of models
