/*
 * classification.h
 *
 *  Created on: Sep 2, 2015
 *      Author: adas
 */

#ifndef CLASSIFICATION_CUH_
#define CLASSIFICATION_CUH_

#include "../common/parameters.h"
#include "../common/detectorData.h"
#include "../utils/cudaUtils.cuh"
#include "SVM/SVMclassification.cuh"

namespace device {

template<typename T, typename C, typename P>
__forceinline__
void SVMclassification(detectorData<T, C, P> *data, dataSizes *dsizes, uint layer, cudaBlockConfig *blkSizes)
{
	dim3 gridSVM(	ceil((float)(dsizes->svm.scoresElems[layer] * WARPSIZE) / blkSizes->svm.blockSVM.x),
					1, 1);
	dim3 gridSVMnaive( ceil((float)dsizes->svm.scoresElems[layer] / blkSizes->svm.blockSVM.x) );

	computeROIwarpReadOnly<P, HISTOWIDTH, XWINBLOCKS, YWINBLOCKS> <<<gridSVM, blkSizes->svm.blockSVM>>>
				(getOffset<P>(data->features.featuresVec0, dsizes->features.numFeaturesElems0, layer),
				 getOffset<P>(data->svm.ROIscores, dsizes->svm.scoresElems, layer),
				 data->svm.weightsM,
				 data->svm.bias,
				 dsizes->svm.scoresElems[layer],
				 dsizes->features.xBlockFeatures[layer]);
	cudaErrorCheck(__LINE__, __FILE__);

	// Naive kernel
//	computeROI<P, HISTOWIDTH, XWINBLOCKS, YWINBLOCKS> <<<gridSVMnaive, blkSizes->svm.blockSVM.x>>>
//								(getOffset<P>(data->features.featuresVec, dsizes->features.numFeaturesElems, layer),
//			 	 	 	 	 	 getOffset<P>(data->svm.ROIscores, dsizes->svm.scoresElems, layer),
//			 	 	 	 	 	 data->svm.weightsM,
//			 	 	 	 	 	 data->svm.bias,
//			 	 	 	 	 	 dsizes->svm.scoresElems[layer],
//			 	 	 	 	 	 dsizes->features.xBlockFeatures[layer]);
//	cudaErrorCheck(__LINE__, __FILE__);


//	P *outscores = (P*) malloc(dsizes->svm.scoresElems[layer] * sizeof(P));
//	cudaMemcpy(outscores,
//			   getOffset<P>(data->svm.ROIscores, dsizes->svm.scoresElems, layer),
//			   dsizes->svm.scoresElems[layer] * sizeof(P),
//			   cudaMemcpyDeviceToHost);
//	for (int i = 0; i < dsizes->svm.scoresElems[layer]; ++i) {
//		cout << "score: " << i << ": " << outscores[i] << endl;
//	}
}


template<typename T, typename C, typename P>
__forceinline__
void SVMclassificationHOGLBP(detectorData<T, C, P> *data, dataSizes *dsizes, uint layer, cudaBlockConfig *blkSizes)
{
	dim3 gridSVM( ceil((float)(dsizes->svm.scoresElems[layer] * WARPSIZE) / blkSizes->svm.blockSVM.x),
				  1, 1);

	computeROIwarpHOGLBP<P, HISTOWIDTH, XWINBLOCKS, YWINBLOCKS> <<<gridSVM, blkSizes->svm.blockSVM>>>
				(getOffset<P>(data->features.featuresVec0, dsizes->features.numFeaturesElems0, layer),
				 getOffset<P>(data->features.featuresVec1, dsizes->features.numFeaturesElems1, layer),
				 getOffset<P>(data->svm.ROIscores, dsizes->svm.scoresElems, layer),
				 data->svm.weightsM,
				 data->svm.bias,
				 dsizes->svm.scoresElems[layer],
				 dsizes->features.xBlockFeatures[layer]);
	cudaErrorCheck(__LINE__, __FILE__);

//	computeROIwarpReadOnly<P, HISTOWIDTH, XWINBLOCKS, YWINBLOCKS> <<<gridSVM, blkSizes->svm.blockSVM>>>
//				(getOffset<P>(data->features.featuresVec0, dsizes->features.numFeaturesElems0, layer),
//				 getOffset<P>(data->svm.ROIscores, dsizes->svm.scoresElems, layer),
//				 data->svm.weightsM,
//				 data->svm.bias,
//				 dsizes->svm.scoresElems[layer],
//				 dsizes->features.xBlockFeatures[layer]);
//	cudaErrorCheck(__LINE__, __FILE__);
}





template<typename T, typename C, typename P>
__forceinline__
void RFclassification(detectorData<T, C, P> *data, dataSizes *dsizes, uint layer, cudaBlockConfig *blkSizes)
{
	cout << "RANDOM FOREST CLASSIFICATION ---------------------------------------------" <<	endl;
}



} /* end namespcae */
#endif /* CLASSIFICATION_CUH_ */
