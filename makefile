NVCC = /usr/local/cuda-11.1/bin/nvcc
CC = g++
#GENCODE_FLAGS = -arch=sm_30

#Optimization flags. Don't use this for debugging.
NVCCFLAGS = -c -m64 -O2 --compiler-options -Wall -Xptxas -O2,-v

#No optimizations. Debugging flags. Use this for debugging.
#NVCCFLAGS = -c -g -G -m64 --compiler-options -Wall

OBJS = classify.o wrappers.o h_classify.o d_classify.o
.SUFFIXES: .cu .o .h 
.cu.o:
	$(NVCC) $(CC_FLAGS) $(NVCCFLAGS) $(GENCODE_FLAGS) $< -o $@

all: classify buildHeaders

classify: $(OBJS)
	$(CC) $(OBJS) -L/usr/local/cuda/lib64 -lcuda -lcudart -ljpeg -o classify

buildHeaders: buildHeaders.c config.h histogram.h
	$(CC) -g buildHeaders.c -o buildHeaders -ljpeg

classify.o: classify.cu wrappers.h h_classify.h d_classify.h config.h histogram.h models.h

h_classify.o: h_classify.cu h_classify.h CHECK.h config.h histogram.h

d_classify.o: d_classify.cu d_classify.h CHECK.h config.h histogram.h

wrappers.o: wrappers.cu wrappers.h

clean:
	rm classify buildHeaders *.o
