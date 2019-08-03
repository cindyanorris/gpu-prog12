
float h_classify(histogramT * h_hgramP, comparisonT * results, histogramT ** models, 
                 int modelCt, unsigned char * Pin, int height, int width); 

void histoOnCPU(histogramT * Phisto, unsigned char * Pin, int height, int width);
