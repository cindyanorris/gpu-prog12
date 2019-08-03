#!/bin/bash

imageDir="images"
for filename in $imageDir/*.jpg; do
   echo " "
   echo "./classify $filename"
   ./classify $filename
   sleep 1
done
