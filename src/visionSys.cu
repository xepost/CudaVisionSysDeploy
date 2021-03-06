#include <stdio.h>
#include <sys/time.h>

#include "init/cParameters.h"
#include "init/cInit.h"
#include "init/cInitSizes.h"

#include "common/detectorData.h"
#include "common/cAdquisition.h"
#include "common/cROIfilter.h"
#include "common/refinementWrapper.h"
//#include "common/Camera.h"
//#include "common/IDSCamera.h"

#include "utils/cudaUtils.cuh"
#include "utils/cudaDataHandler.h"
#include "utils/nvtxHandler.h"
//#include "cuda_fp16.h"

#include "device/ImageProcessing/colorTransformation.cuh"

//////////////////////////////////////
// Type definition for the algorithms
//////////////////////////////////////
typedef uchar 		input_t;
typedef int 		desc_t;
typedef float		roifeat_t;
//////////////////////////////////////

int main()
{
	// Read application parameters
	cParameters paramsHandle;
	paramsHandle.readParameters();
	parameters *params = paramsHandle.getParams();

	// Initialize Acquisition handler and read image
	cAcquisition acquisition(params);
	//acquisition.readAllimages();
	cv::Mat *rawImg = acquisition.acquireFrameRGB();

	// Initialize dataSizes structure
	cInitSizes sizesHandler(params, rawImg->rows, rawImg->cols);
	dataSizes *dSizes = sizesHandler.getDsizes();

	// Initialize Algorithm Handler and pointers to functions to initialize algorithm
	cInit init(params);
	detectorFunctions<input_t, desc_t, roifeat_t> detectorF;
	detectorF = init.algorithmHandler<input_t, desc_t, roifeat_t>();

	// Initialize Algorithm Data structures
	detectorData<input_t, desc_t, roifeat_t> detectData;
	detectorF.initPyramid(&detectData, dSizes, dSizes->pyr.pyramidLayers);
	detectorF.initFeatures(&detectData, dSizes, dSizes->pyr.pyramidLayers);
	detectorF.initClassifi(&detectData, dSizes, dSizes->pyr.pyramidLayers, params->pathToSVMmodel);

	// Initialize ROI filtering object
	cROIfilter<roifeat_t> ROIfilter(params, dSizes);

	// Initialize refinement object
	refinementWrapper refinement;

	// Set up CUDA configuration and device to be used
	cInitCuda cudaConf(params);
	cudaBlockConfig blkconfig = cudaConf.getBlockConfig();
	cudaConf.printDeviceInfo();

	// Create Device data manager
	DeviceDataHandler devDataHandler;

	// Allocate RGB and GRAYSCALE raw images
	init.allocateRawImage<input_t>(&(detectData.rawImg), dSizes->rawSize);  //TODO: add allocation on host
	init.allocateRawImage<input_t>(&(detectData.rawImgBW), dSizes->rawSizeBW);

	// Start the timer
	time_t start;
	time(&start);

	timeval startVal, endVal;
	gettimeofday(&startVal, 0);

	// Start the counter of iterations
	int count = 0;
	const int iterations = 5;

	// Image processing loop
	while (!rawImg->empty() && count < iterations)
	//for (int ite = 0; ite < 1 /*acquisition.getDiskImages()->size()-1*/; ite++)
	{
		NVTXhandler lat(COLOR_GREEN, "latency");
		lat.nvtxStartEvent();
		count++;

		// Copy each frame to device
		copyHtoD<input_t>(detectData.rawImg, rawImg->data, dSizes->rawSize);
		//acquisition.setCurrentFrame(0);
		//copyHtoD<input_t>(detectData.rawImg, acquisition.getCurrentFrame()->data, dSizes->rawSize);

		// Input image preprocessing
		detectorF.preprocess(&detectData, dSizes, &blkconfig);

		// Compute the pyramid
		NVTXhandler pyramide(COLOR_ORANGE, "Pyramid");
		pyramide.nvtxStartEvent();

		detectorF.pyramid(&detectData, dSizes, &blkconfig);

		pyramide.nvtxStopEvent();

		// Detection algorithm for each pyramid layer
		for (uint i = 0; i < dSizes->pyr.pyramidLayers; i++) {
			detectorF.featureExtraction(&detectData, dSizes, i, &blkconfig);
//			cv::Mat inp, lbp;
//
//			string name = "00000002a_LBP_";
//			stringstream stream;
//			stream << name;
//			stream << i;
//			stream << ".tif";
//			cout << stream.str() << endl;
//			//name = name + (string)i;
//			lbp = cv::imread(stream.str(), CV_LOAD_IMAGE_GRAYSCALE);
//			if (lbp.cols == 0)
//				cout << "unable to read GT lbp images" << endl;
//			//cv::cvtColor(inp, lbp, CV_BGR2GRAY);
//
//			cout << "GT lbp: rows:" << lbp.rows << "  cols:  " << lbp.cols << endl;
//			cout << "CUDA lbp: rows:" << dSizes->imgRows[i] << "  cols:  " << dSizes->imgCols[i] << endl;
//
//			cv::Mat lbpcuda(lbp.rows, lbp.cols, CV_8UC1);
//
//			copyDtoH(lbpcuda.data, getOffset(detectData.imgDescriptor, dSizes->imgDescElems, i), dSizes->imgDescElems[i]);
//			stream << "GT";
//			cv::imshow(stream.str(), lbp);
//			cv::waitKey(0);
//			stream << "CUDA";
//			cv::imshow(stream.str(), lbpcuda);
//			cv::waitKey(0);
//			cv::imwrite("cudalbp.png", lbpcuda);
//
//			cv::Mat dif(lbp.rows, lbp.cols, CV_8UC1);
//			cv::absdiff(lbpcuda,lbp, dif);
//			//dif = lbp - lbpcuda;
//			cv::imshow("diference", dif);
//			cv::waitKey(0);
///////////////////////////////////////////////////////////
//			uchar *cell = (uchar*)malloc(dSizes->cellHistosElems[i]);
//			copyDtoH(cell, detectData.cellHistos, dSizes->cellHistosElems[i]);
//			for (int u = 0; u < dSizes->cellHistosElems[i]; u++) {
//				printf( "cell feature: %d: %d\n", u, cell[u]);
//			}

			detectorF.classification(&detectData, dSizes, i, &blkconfig);

			copyDtoH<roifeat_t>(getOffset<roifeat_t>(ROIfilter.getHostScoresVector(), dSizes->svm.scoresElems, i),
								getOffset<roifeat_t>(detectData.svm.ROIscores, dSizes->svm.scoresElems, i),
								dSizes->svm.scoresElems[i]);

			ROIfilter.roisDecision(i, dSizes->pyr.scalesResizeFactor[i], dSizes->pyr.xBorder, dSizes->pyr.yBorder, params->minRoiMargin);
		}
		// Non-Max supression refinement
		NVTXhandler nms(COLOR_BLUE, "Non maximum suppression");
		nms.nvtxStartEvent();

		refinement.AccRefinement(ROIfilter.getHitROIs());
		refinement.drawRois(*(acquisition.getCurrentFrame()));

		nms.nvtxStopEvent();

		// Clear vector for the next iteration
		NVTXhandler clearVecs(COLOR_YELLOW, "Reset nms Vectors");
		clearVecs.nvtxStartEvent();

		ROIfilter.clearVector();
		refinement.clearVector();

		clearVecs.nvtxStopEvent();

		// Show the frame
		NVTXhandler showF(COLOR_RED, "Show frame");
		showF.nvtxStartEvent();

		//acquisition.showFrame();

		showF.nvtxStopEvent();

		//Acquisition of the new frame
		NVTXhandler frameTime(COLOR_GREEN, "Frame adquisition");
		frameTime.nvtxStartEvent();
		// Get a new frame
//		char str[256];
//		sprintf(str, "%d.png", count);
//		cv::imwrite(str, *rawImg);

		rawImg = acquisition.acquireFrameRGB();

		frameTime.nvtxStopEvent();


		NVTXhandler resetFeat(COLOR_ORANGE, "Reset device Features");
		resetFeat.nvtxStartEvent();
		// Reset device data structures
		detectorF.resetFeatures(&detectData, dSizes);
		resetFeat.nvtxStopEvent();

		lat.nvtxStopEvent();

	}

	// Stop the timer
	time_t end;
	time(&end);

	gettimeofday(&endVal, 0);

	//printf("elapsed time: %lu \n", (endVal.tv_usec - startVal.tv_usec));

	// Get the elapsed time
	double seconds = difftime(end, start);
	cout << "FPS : " << iterations / seconds << endl;
	cout << "elapsed secs: " << seconds << endl;

	cudaErrorCheck();
	return 0;
}
