// Copyright 2019-2020 CERN and copyright holders of ALICE O2.
// See https://alice-o2.web.cern.ch/copyright for details of the copyright holders.
// All rights not expressly granted are reserved.
//
// This software is distributed under the terms of the GNU General Public
// License v3 (GPL Version 3), copied verbatim in the file "COPYING".
//
// In applying this license CERN does not waive the privileges and immunities
// granted to it by virtue of its status as an Intergovernmental Organization
// or submit itself to any jurisdiction.

/// \file GPUReconstructionHIP.hip.cxx
/// \author David Rohr

#define __HIP_ENABLE_DEVICE_MALLOC__ 1 // Fix SWDEV-239120
#define GPUCA_UNROLL(CUDA, HIP) GPUCA_M_UNROLL_##HIP
#define GPUdic(CUDA, HIP) GPUCA_GPUdic_select_##HIP()

#include "GPUReconstructionHIPIncludes.h"

#include "GPUDef.h"

// clang-format off
#ifndef GPUCA_NO_CONSTANT_MEMORY
  #define GPUCA_CONSMEM_PTR
  #define GPUCA_CONSMEM_CALL
  #define GPUCA_CONSMEM (gGPUConstantMemBuffer.v)
#else
  #define GPUCA_CONSMEM_PTR const GPUConstantMem *gGPUConstantMemBuffer,
  #define GPUCA_CONSMEM_CALL me->mDeviceConstantMem,
  #define GPUCA_CONSMEM const_cast<GPUConstantMem&>(*gGPUConstantMemBuffer)
#endif
#define GPUCA_KRNL_BACKEND_CLASS GPUReconstructionHIPBackend
// clang-format on

#include "GPUReconstructionHIP.h"
#include "GPUReconstructionHIPInternals.h"
#include "HIPThrustHelpers.h"
#include "GPUReconstructionIncludes.h"

using namespace GPUCA_NAMESPACE::gpu;

#ifdef GPUCA_HAS_GLOBAL_SYMBOL_CONSTANT_MEM
__global__ void gGPUConstantMemBuffer_dummy(int* p) { *p = *(int*)&gGPUConstantMemBuffer; }
#endif

__global__ void dummyInitKernel(void*) {}

#include "GPUReconstructionIncludesITS.h"

class GPUDebugTiming
{
 public:
  GPUDebugTiming(bool d, void** t, hipStream_t* s, GPUReconstruction::krnlSetup& x, GPUReconstructionHIPBackend* r) : mDeviceTimers(t), mStreams(s), mXYZ(x), mRec(r), mDo(d)
  {
    if (mDo) {
      if (mDeviceTimers) {
        mRec->GPUFailedMsg(hipEventRecord((hipEvent_t)mDeviceTimers[0], mStreams[mXYZ.x.stream]));
      } else {
        mTimer.ResetStart();
      }
    }
  }
  ~GPUDebugTiming()
  {
    if (mDo) {
      if (mDeviceTimers) {
        mRec->GPUFailedMsg(hipEventRecord((hipEvent_t)mDeviceTimers[1], mStreams[mXYZ.x.stream]));
        mRec->GPUFailedMsg(hipEventSynchronize((hipEvent_t)mDeviceTimers[1]));
        float v;
        mRec->GPUFailedMsg(hipEventElapsedTime(&v, (hipEvent_t)mDeviceTimers[0], (hipEvent_t)mDeviceTimers[1]));
        mXYZ.t = v * 1.e-3;
      } else {
        mRec->GPUFailedMsg(hipStreamSynchronize(mStreams[mXYZ.x.stream]));
        mXYZ.t = mTimer.GetCurrentElapsedTime();
      }
    }
  }

 private:
  GPUReconstruction::deviceEvent* mDeviceTimers;
  hipStream_t* mStreams;
  GPUReconstruction::krnlSetup& mXYZ;
  GPUReconstructionHIPBackend* mRec;
  HighResTimer mTimer;
  bool mDo;
};

#include "GPUReconstructionIncludesDevice.h"

#undef GPUCA_KRNL_REG
#define GPUCA_KRNL_REG(args) __launch_bounds__(GPUCA_M_MAX2_3(GPUCA_M_STRIP(args)))
#undef GPUCA_KRNL_CUSTOM
#define GPUCA_KRNL_CUSTOM(args) GPUCA_M_STRIP(args)
#undef GPUCA_KRNL_BACKEND_XARGS
#define GPUCA_KRNL_BACKEND_XARGS hipEvent_t *debugStartEvent, hipEvent_t *debugStopEvent,
#define GPUCA_KRNL(x_class, x_attributes, x_arguments, x_forward) \
  GPUCA_KRNL_PROP(x_class, x_attributes)                          \
  GPUCA_KRNL_WRAP(GPUCA_KRNL_, x_class, x_attributes, x_arguments, x_forward)
#define GPUCA_KRNL_CALL_single(x_class, x_attributes, x_arguments, x_forward)                                                                                                                                                                   \
  if (debugStartEvent == nullptr) {                                                                                                                                                                                                             \
    hipLaunchKernelGGL(HIP_KERNEL_NAME(GPUCA_M_CAT(krnl_, GPUCA_M_KRNL_NAME(x_class))), dim3(x.nBlocks), dim3(x.nThreads), 0, me->mInternals->Streams[x.stream], GPUCA_CONSMEM_CALL y.start, args...);                                          \
  } else {                                                                                                                                                                                                                                      \
    hipExtLaunchKernelGGL(HIP_KERNEL_NAME(GPUCA_M_CAT(krnl_, GPUCA_M_KRNL_NAME(x_class))), dim3(x.nBlocks), dim3(x.nThreads), 0, me->mInternals->Streams[x.stream], *debugStartEvent, *debugStopEvent, 0, GPUCA_CONSMEM_CALL y.start, args...); \
  }
#define GPUCA_KRNL_CALL_multi(x_class, x_attributes, x_arguments, x_forward)                                                                                                                                                                                    \
  if (debugStartEvent == nullptr) {                                                                                                                                                                                                                             \
    hipLaunchKernelGGL(HIP_KERNEL_NAME(GPUCA_M_CAT3(krnl_, GPUCA_M_KRNL_NAME(x_class), _multi)), dim3(x.nBlocks), dim3(x.nThreads), 0, me->mInternals->Streams[x.stream], GPUCA_CONSMEM_CALL y.start, y.num, args...);                                          \
  } else {                                                                                                                                                                                                                                                      \
    hipExtLaunchKernelGGL(HIP_KERNEL_NAME(GPUCA_M_CAT3(krnl_, GPUCA_M_KRNL_NAME(x_class), _multi)), dim3(x.nBlocks), dim3(x.nThreads), 0, me->mInternals->Streams[x.stream], *debugStartEvent, *debugStopEvent, 0, GPUCA_CONSMEM_CALL y.start, y.num, args...); \
  }
#include "GPUReconstructionKernels.h"
#undef GPUCA_KRNL

template <>
void GPUReconstructionHIPBackend::runKernelBackendInternal<GPUMemClean16, 0>(krnlSetup& _xyz, void* const& ptr, unsigned long const& size)
{
  GPUDebugTiming timer(mProcessingSettings.debugLevel, nullptr, mInternals->Streams, _xyz, this);
  GPUFailedMsg(hipMemsetAsync(ptr, 0, size, mInternals->Streams[_xyz.x.stream]));
}

template <class T, int I, typename... Args>
void GPUReconstructionHIPBackend::runKernelBackendInternal(krnlSetup& _xyz, const Args&... args)
{
  if (mProcessingSettings.deviceTimers && mProcessingSettings.debugLevel > 0) {
    backendInternal<T, I>::runKernelBackendMacro(_xyz, this, (hipEvent_t*)&mDebugEvents->DebugStart, (hipEvent_t*)&mDebugEvents->DebugStop, args...);
    GPUFailedMsg(hipEventSynchronize((hipEvent_t)mDebugEvents->DebugStop));
    float v;
    GPUFailedMsg(hipEventElapsedTime(&v, (hipEvent_t)mDebugEvents->DebugStart, (hipEvent_t)mDebugEvents->DebugStop));
    _xyz.t = v * 1.e-3;
  } else {
    backendInternal<T, I>::runKernelBackendMacro(_xyz, this, nullptr, nullptr, args...);
  }
}

template <class T, int I, typename... Args>
int GPUReconstructionHIPBackend::runKernelBackend(krnlSetup& _xyz, const Args&... args)
{
  auto& x = _xyz.x;
  auto& z = _xyz.z;
  if (z.evList) {
    for (int k = 0; k < z.nEvents; k++) {
      GPUFailedMsg(hipStreamWaitEvent(mInternals->Streams[x.stream], ((hipEvent_t*)z.evList)[k], 0));
    }
  }
  runKernelBackendInternal<T, I>(_xyz, args...);
  GPUFailedMsg(hipGetLastError());
  if (z.ev) {
    GPUFailedMsg(hipEventRecord(*(hipEvent_t*)z.ev, mInternals->Streams[x.stream]));
  }
  return 0;
}

GPUReconstructionHIPBackend::GPUReconstructionHIPBackend(const GPUSettingsDeviceBackend& cfg) : GPUReconstructionDeviceBase(cfg, sizeof(GPUReconstructionDeviceBase))
{
  if (mMaster == nullptr) {
    mInternals = new GPUReconstructionHIPInternals;
  }
  mDeviceBackendSettings.deviceType = DeviceType::HIP;
}

GPUReconstructionHIPBackend::~GPUReconstructionHIPBackend()
{
  Exit(); // Make sure we destroy everything (in particular the ITS tracker) before we exit
  if (mMaster == nullptr) {
    delete mInternals;
  }
}

int GPUReconstructionHIPBackend::GPUFailedMsgAI(const long long int error, const char* file, int line)
{
  // Check for HIP Error and in the case of an error display the corresponding error string
  if (error == hipSuccess) {
    return (0);
  }
  GPUError("HIP Error: %lld / %s (%s:%d)", error, hipGetErrorString((hipError_t)error), file, line);
  return 1;
}

void GPUReconstructionHIPBackend::GPUFailedMsgA(const long long int error, const char* file, int line)
{
  if (GPUFailedMsgAI(error, file, line)) {
    static bool runningCallbacks = false;
    if (IsInitialized() && runningCallbacks == false) {
      runningCallbacks = true;
      CheckErrorCodes(false, true);
    }
    throw std::runtime_error("HIP Failure");
  }
}

GPUReconstruction* GPUReconstruction_Create_HIP(const GPUSettingsDeviceBackend& cfg) { return new GPUReconstructionHIP(cfg); }

void GPUReconstructionHIPBackend::GetITSTraits(std::unique_ptr<o2::its::TrackerTraits>* trackerTraits, std::unique_ptr<o2::its::VertexerTraits>* vertexerTraits, std::unique_ptr<o2::its::TimeFrame>* timeFrame)
{
  if (trackerTraits) {
    trackerTraits->reset(new o2::its::TrackerTraitsGPU);
  }
  if (vertexerTraits) {
    vertexerTraits->reset(new o2::its::VertexerTraitsGPU);
  }
  if (timeFrame) {
    timeFrame->reset(new o2::its::gpu::TimeFrameGPU);
  }
}

void GPUReconstructionHIPBackend::UpdateAutomaticProcessingSettings()
{
  GPUCA_GPUReconstructionUpdateDefaults();
}

int GPUReconstructionHIPBackend::InitDevice_Runtime()
{
  if (mMaster == nullptr) {
    hipDeviceProp_t hipDeviceProp;
    int count, bestDevice = -1;
    double bestDeviceSpeed = -1, deviceSpeed;
    if (GPUFailedMsgI(hipGetDeviceCount(&count))) {
      GPUError("Error getting HIP Device Count");
      return (1);
    }
    if (mProcessingSettings.debugLevel >= 2) {
      GPUInfo("Available HIP devices:");
    }
    std::vector<bool> devicesOK(count, false);
    std::vector<size_t> devMemory(count, 0);
    bool contextCreated = false;
    for (int i = 0; i < count; i++) {
      if (mProcessingSettings.debugLevel >= 4) {
        GPUInfo("Examining device %d", i);
      }
      size_t free, total;
      if (GPUFailedMsgI(hipSetDevice(i))) {
        if (mProcessingSettings.debugLevel >= 4) {
          GPUWarning("Couldn't create context for device %d. Skipping it.", i);
        }
        continue;
      }
      contextCreated = true;
      if (GPUFailedMsgI(hipMemGetInfo(&free, &total))) {
        if (mProcessingSettings.debugLevel >= 4) {
          GPUWarning("Error obtaining HIP memory info about device %d! Skipping it.", i);
        }
        GPUFailedMsg(hipDeviceReset());
        continue;
      }
      if (count > 1) {
        GPUFailedMsg(hipDeviceReset());
        contextCreated = false;
      }
      if (mProcessingSettings.debugLevel >= 4) {
        GPUInfo("Obtained current memory usage for device %d", i);
      }
      if (GPUFailedMsgI(hipGetDeviceProperties(&hipDeviceProp, i))) {
        continue;
      }
      if (mProcessingSettings.debugLevel >= 4) {
        GPUInfo("Obtained device properties for device %d", i);
      }
      int deviceOK = true;
      const char* deviceFailure = "";

      deviceSpeed = (double)hipDeviceProp.multiProcessorCount * (double)hipDeviceProp.clockRate * (double)hipDeviceProp.warpSize * (double)hipDeviceProp.major * (double)hipDeviceProp.major;
      if (mProcessingSettings.debugLevel >= 2) {
        GPUImportant("Device %s%2d: %s (Rev: %d.%d - Mem %lld)%s %s", deviceOK ? " " : "[", i, hipDeviceProp.name, hipDeviceProp.major, hipDeviceProp.minor, (long long int)hipDeviceProp.totalGlobalMem, deviceOK ? " " : " ]", deviceOK ? "" : deviceFailure);
      }
      if (!deviceOK) {
        continue;
      }
      devicesOK[i] = true;
      if (deviceSpeed > bestDeviceSpeed) {
        bestDevice = i;
        bestDeviceSpeed = deviceSpeed;
      } else {
        if (mProcessingSettings.debugLevel >= 2 && mProcessingSettings.deviceNum < 0) {
          GPUInfo("Skipping: Speed %f < %f\n", deviceSpeed, bestDeviceSpeed);
        }
      }
    }
    bool noDevice = false;
    if (bestDevice == -1) {
      GPUWarning("No %sHIP Device available, aborting HIP Initialisation (Required mem: %lld)", count ? "appropriate " : "", (long long int)mDeviceMemorySize);
      noDevice = true;
    } else if (mProcessingSettings.deviceNum > -1) {
      if (mProcessingSettings.deviceNum >= (signed)count) {
        GPUWarning("Requested device ID %d does not exist", mProcessingSettings.deviceNum);
        noDevice = true;
      } else if (!devicesOK[mProcessingSettings.deviceNum]) {
        GPUWarning("Unsupported device requested (%d)", mProcessingSettings.deviceNum);
        noDevice = true;
      } else {
        bestDevice = mProcessingSettings.deviceNum;
      }
    }
    if (noDevice) {
      if (contextCreated) {
        GPUFailedMsgI(hipDeviceReset());
      }
      return (1);
    }
    mDeviceId = bestDevice;

    GPUFailedMsgI(hipGetDeviceProperties(&hipDeviceProp, mDeviceId));

    if (mProcessingSettings.debugLevel >= 2) {
      GPUInfo("Using HIP Device %s with Properties:", hipDeviceProp.name);
      GPUInfo("\ttotalGlobalMem = %lld", (unsigned long long int)hipDeviceProp.totalGlobalMem);
      GPUInfo("\tsharedMemPerBlock = %lld", (unsigned long long int)hipDeviceProp.sharedMemPerBlock);
      GPUInfo("\tregsPerBlock = %d", hipDeviceProp.regsPerBlock);
      GPUInfo("\twarpSize = %d", hipDeviceProp.warpSize);
      GPUInfo("\tmaxThreadsPerBlock = %d", hipDeviceProp.maxThreadsPerBlock);
      GPUInfo("\tmaxThreadsDim = %d %d %d", hipDeviceProp.maxThreadsDim[0], hipDeviceProp.maxThreadsDim[1], hipDeviceProp.maxThreadsDim[2]);
      GPUInfo("\tmaxGridSize = %d %d %d", hipDeviceProp.maxGridSize[0], hipDeviceProp.maxGridSize[1], hipDeviceProp.maxGridSize[2]);
      GPUInfo("\ttotalConstMem = %lld", (unsigned long long int)hipDeviceProp.totalConstMem);
      GPUInfo("\tmajor = %d", hipDeviceProp.major);
      GPUInfo("\tminor = %d", hipDeviceProp.minor);
      GPUInfo("\tclockRate = %d", hipDeviceProp.clockRate);
      GPUInfo("\tmemoryClockRate = %d", hipDeviceProp.memoryClockRate);
      GPUInfo("\tmultiProcessorCount = %d", hipDeviceProp.multiProcessorCount);
      GPUInfo(" ");
    }
    if (hipDeviceProp.warpSize != GPUCA_WARP_SIZE) {
      throw std::runtime_error("Invalid warp size on GPU");
    }
    mBlockCount = hipDeviceProp.multiProcessorCount;
    mMaxThreads = std::max<int>(mMaxThreads, hipDeviceProp.maxThreadsPerBlock * mBlockCount);
    mWarpSize = 64;
    mDeviceName = hipDeviceProp.name;
    mDeviceName += " (HIP GPU)";

    if (hipDeviceProp.major < 3) {
      GPUError("Unsupported HIP Device");
      return (1);
    }
#ifndef GPUCA_NO_CONSTANT_MEMORY
    if (gGPUConstantMemBufferSize > hipDeviceProp.totalConstMem) {
      GPUError("Insufficient constant memory available on GPU %d < %d!", (int)hipDeviceProp.totalConstMem, (int)gGPUConstantMemBufferSize);
      return (1);
    }
#endif

    if (contextCreated == 0 && GPUFailedMsgI(hipSetDevice(mDeviceId))) {
      GPUError("Could not set HIP Device!");
      return (1);
    }
    if (GPUFailedMsgI(hipSetDeviceFlags(hipDeviceScheduleBlockingSync))) {
      GPUError("Could not set HIP Device!");
      return (1);
    }

    /*if (GPUFailedMsgI(hipDeviceSetLimit(hipLimitStackSize, GPUCA_GPU_STACK_SIZE)))
    {
      GPUError("Error setting HIP stack size");
      GPUFailedMsgI(hipDeviceReset());
      return(1);
    }*/

    if (mDeviceMemorySize > hipDeviceProp.totalGlobalMem || GPUFailedMsgI(hipMalloc(&mDeviceMemoryBase, mDeviceMemorySize))) {
      size_t free, total;
      GPUFailedMsg(hipMemGetInfo(&free, &total));
      GPUError("HIP Memory Allocation Error (trying %lld bytes, %lld available on GPU, %lld free)", (long long int)mDeviceMemorySize, (long long int)hipDeviceProp.totalGlobalMem, (long long int)free);
      GPUFailedMsgI(hipDeviceReset());
      return (1);
    }
    if (GPUFailedMsgI(hipHostMalloc(&mHostMemoryBase, mHostMemorySize))) {
      GPUError("Error allocating Page Locked Host Memory (trying %lld bytes)", (long long int)mHostMemorySize);
      GPUFailedMsgI(hipDeviceReset());
      return (1);
    }
    if (mProcessingSettings.debugLevel >= 1) {
      GPUInfo("Memory ptrs: GPU (%lld bytes): %p - Host (%lld bytes): %p", (long long int)mDeviceMemorySize, mDeviceMemoryBase, (long long int)mHostMemorySize, mHostMemoryBase);
      memset(mHostMemoryBase, 0, mHostMemorySize);
      if (GPUFailedMsgI(hipMemset(mDeviceMemoryBase, 0xDD, mDeviceMemorySize))) {
        GPUError("Error during HIP memset");
        GPUFailedMsgI(hipDeviceReset());
        return (1);
      }
    }

    for (int i = 0; i < mNStreams; i++) {
      if (GPUFailedMsgI(hipStreamCreate(&mInternals->Streams[i]))) {
        GPUError("Error creating HIP Stream");
        GPUFailedMsgI(hipDeviceReset());
        return (1);
      }
    }

    void* devPtrConstantMem;
#ifndef GPUCA_NO_CONSTANT_MEMORY
    if (GPUFailedMsgI(hipGetSymbolAddress(&devPtrConstantMem, HIP_SYMBOL(gGPUConstantMemBuffer)))) {
      GPUError("Error getting ptr to constant memory");
      GPUFailedMsgI(hipDeviceReset());
      return 1;
    }
#else
    if (GPUFailedMsgI(hipMalloc(&devPtrConstantMem, gGPUConstantMemBufferSize))) {
      GPUError("HIP Memory Allocation Error");
      GPUFailedMsgI(hipDeviceReset());
      return (1);
    }
#endif
    mDeviceConstantMem = (GPUConstantMem*)devPtrConstantMem;

    hipLaunchKernelGGL(HIP_KERNEL_NAME(dummyInitKernel), dim3(mBlockCount), dim3(256), 0, 0, mDeviceMemoryBase);
    GPUInfo("HIP Initialisation successfull (Device %d: %s (Frequency %d, Cores %d), %lld / %lld bytes host / global memory, Stack frame %d, Constant memory %lld)", mDeviceId, hipDeviceProp.name, hipDeviceProp.clockRate, hipDeviceProp.multiProcessorCount, (long long int)mHostMemorySize, (long long int)mDeviceMemorySize, (int)GPUCA_GPU_STACK_SIZE, (long long int)gGPUConstantMemBufferSize);
  } else {
    GPUReconstructionHIPBackend* master = dynamic_cast<GPUReconstructionHIPBackend*>(mMaster);
    mDeviceId = master->mDeviceId;
    mBlockCount = master->mBlockCount;
    mWarpSize = master->mWarpSize;
    mMaxThreads = master->mMaxThreads;
    mDeviceName = master->mDeviceName;
    mDeviceConstantMem = master->mDeviceConstantMem;
    mInternals = master->mInternals;
    GPUFailedMsgI(hipSetDevice(mDeviceId));
    GPUInfo("HIP Initialized from master");
  }
  for (unsigned int i = 0; i < mEvents.size(); i++) {
    hipEvent_t* events = (hipEvent_t*)mEvents[i].data();
    for (unsigned int j = 0; j < mEvents[i].size(); j++) {
      if (GPUFailedMsgI(hipEventCreateWithFlags(&events[j], hipEventBlockingSync))) {
        GPUError("Error creating event");
        GPUFailedMsgI(hipDeviceReset());
        return 1;
      }
    }
  }

  return (0);
}

int GPUReconstructionHIPBackend::ExitDevice_Runtime()
{
  // Uninitialize HIP
  GPUFailedMsgI(hipSetDevice(mDeviceId));
  SynchronizeGPU();
  unregisterRemainingRegisteredMemory();

  for (unsigned int i = 0; i < mEvents.size(); i++) {
    hipEvent_t* events = (hipEvent_t*)mEvents[i].data();
    for (unsigned int j = 0; j < mEvents[i].size(); j++) {
      GPUFailedMsgI(hipEventDestroy(events[j]));
    }
  }

  if (mMaster == nullptr) {
    GPUFailedMsgI(hipFree(mDeviceMemoryBase));

#ifdef GPUCA_NO_CONSTANT_MEMORY
    GPUFailedMsgI(hipFree(mDeviceConstantMem));
#endif

    for (int i = 0; i < mNStreams; i++) {
      GPUFailedMsgI(hipStreamDestroy(mInternals->Streams[i]));
    }

    GPUFailedMsgI(hipHostFree(mHostMemoryBase));
    GPUFailedMsgI(hipDeviceReset());
    GPUInfo("HIP Uninitialized");
  }
  mHostMemoryBase = nullptr;
  mDeviceMemoryBase = nullptr;

  /*if (GPUFailedMsgI(hipDeviceReset())) { // No longer doing this, another thread might use the GPU
    GPUError("Could not uninitialize GPU");
    return (1);
  }*/

  return (0);
}

size_t GPUReconstructionHIPBackend::GPUMemCpy(void* dst, const void* src, size_t size, int stream, int toGPU, deviceEvent ev, deviceEvent* evList, int nEvents)
{
  if (mProcessingSettings.debugLevel >= 3) {
    stream = -1;
  }
  if (stream == -1) {
    SynchronizeGPU();
    GPUFailedMsg(hipMemcpy(dst, src, size, toGPU ? hipMemcpyHostToDevice : hipMemcpyDeviceToHost));
  } else {
    if (evList == nullptr) {
      nEvents = 0;
    }
    for (int k = 0; k < nEvents; k++) {
      GPUFailedMsg(hipStreamWaitEvent(mInternals->Streams[stream], ((hipEvent_t*)evList)[k], 0));
    }
    GPUFailedMsg(hipMemcpyAsync(dst, src, size, toGPU == -2 ? hipMemcpyDeviceToDevice : toGPU ? hipMemcpyHostToDevice : hipMemcpyDeviceToHost, mInternals->Streams[stream]));
  }
  if (ev) {
    GPUFailedMsg(hipEventRecord(*(hipEvent_t*)ev, mInternals->Streams[stream == -1 ? 0 : stream]));
  }
  return size;
}

size_t GPUReconstructionHIPBackend::TransferMemoryInternal(GPUMemoryResource* res, int stream, deviceEvent ev, deviceEvent* evList, int nEvents, bool toGPU, const void* src, void* dst)
{
  if (!(res->Type() & GPUMemoryResource::MEMORY_GPU)) {
    if (mProcessingSettings.debugLevel >= 4) {
      GPUInfo("Skipped transfer of non-GPU memory resource: %s", res->Name());
    }
    return 0;
  }
  if (mProcessingSettings.debugLevel >= 3 && (strcmp(res->Name(), "ErrorCodes") || mProcessingSettings.debugLevel >= 4)) {
    GPUInfo("Copying to %s: %s - %lld bytes", toGPU ? "GPU" : "Host", res->Name(), (long long int)res->Size());
  }
  return GPUMemCpy(dst, src, res->Size(), stream, toGPU, ev, evList, nEvents);
}

size_t GPUReconstructionHIPBackend::WriteToConstantMemory(size_t offset, const void* src, size_t size, int stream, deviceEvent ev)
{
#ifndef GPUCA_NO_CONSTANT_MEMORY
  if (stream == -1) {
    GPUFailedMsg(hipMemcpyToSymbol(HIP_SYMBOL(gGPUConstantMemBuffer), src, size, offset, hipMemcpyHostToDevice));
  } else {
    GPUFailedMsg(hipMemcpyToSymbolAsync(HIP_SYMBOL(gGPUConstantMemBuffer), src, size, offset, hipMemcpyHostToDevice, mInternals->Streams[stream]));
  }
  if (ev && stream != -1) {
    GPUFailedMsg(hipEventRecord(*(hipEvent_t*)ev, mInternals->Streams[stream]));
  }
#else
  if (stream == -1) {
    GPUFailedMsg(hipMemcpy(((char*)mDeviceConstantMem) + offset, src, size, hipMemcpyHostToDevice));
  } else {
    GPUFailedMsg(hipMemcpyAsync(((char*)mDeviceConstantMem) + offset, src, size, hipMemcpyHostToDevice, mInternals->Streams[stream]));
  }
#endif
  return size;
}

void GPUReconstructionHIPBackend::ReleaseEvent(deviceEvent ev) {}

void GPUReconstructionHIPBackend::RecordMarker(deviceEvent ev, int stream) { GPUFailedMsg(hipEventRecord(*(hipEvent_t*)ev, mInternals->Streams[stream])); }

std::unique_ptr<GPUReconstruction::GPUThreadContext> GPUReconstructionHIPBackend::GetThreadContext()
{
  GPUFailedMsg(hipSetDevice(mDeviceId));
  return std::unique_ptr<GPUThreadContext>(new GPUThreadContext);
}

void GPUReconstructionHIPBackend::SynchronizeGPU() { GPUFailedMsg(hipDeviceSynchronize()); }

void GPUReconstructionHIPBackend::SynchronizeStream(int stream) { GPUFailedMsg(hipStreamSynchronize(mInternals->Streams[stream])); }

void GPUReconstructionHIPBackend::SynchronizeEvents(deviceEvent* evList, int nEvents)
{
  for (int i = 0; i < nEvents; i++) {
    GPUFailedMsg(hipEventSynchronize(((hipEvent_t*)evList)[i]));
  }
}

void GPUReconstructionHIPBackend::StreamWaitForEvents(int stream, deviceEvent* evList, int nEvents)
{
  for (int i = 0; i < nEvents; i++) {
    GPUFailedMsg(hipStreamWaitEvent(mInternals->Streams[stream], ((hipEvent_t*)evList)[i], 0));
  }
}

bool GPUReconstructionHIPBackend::IsEventDone(deviceEvent* evList, int nEvents)
{
  for (int i = 0; i < nEvents; i++) {
    hipError_t retVal = hipEventSynchronize(((hipEvent_t*)evList)[i]);
    if (retVal == hipErrorNotReady) {
      return false;
    }
    GPUFailedMsg(retVal);
  }
  return (true);
}

int GPUReconstructionHIPBackend::GPUDebug(const char* state, int stream, bool force)
{
  // Wait for HIP-Kernel to finish and check for HIP errors afterwards, in case of debugmode
  hipError_t hipErr;
  hipErr = hipGetLastError();
  if (hipErr != hipSuccess) {
    GPUError("HIP Error %s while running kernel (%s) (Stream %d)", hipGetErrorString(hipErr), state, stream);
    return (1);
  }
  if (!force && mProcessingSettings.debugLevel <= 0) {
    return (0);
  }
  if (GPUFailedMsgI(hipDeviceSynchronize())) {
    GPUError("HIP Error while synchronizing (%s) (Stream %d)", state, stream);
    return (1);
  }
  if (mProcessingSettings.debugLevel >= 3) {
    GPUInfo("GPU Sync Done");
  }
  return (0);
}

int GPUReconstructionHIPBackend::registerMemoryForGPU_internal(const void* ptr, size_t size)
{
  return GPUFailedMsgI(hipHostRegister((void*)ptr, size, hipHostRegisterDefault));
}

int GPUReconstructionHIPBackend::unregisterMemoryForGPU_internal(const void* ptr)
{
  return GPUFailedMsgI(hipHostUnregister((void*)ptr));
}

void* GPUReconstructionHIPBackend::getGPUPointer(void* ptr)
{
  void* retVal = nullptr;
  GPUFailedMsg(hipHostGetDevicePointer(&retVal, ptr, 0));
  return retVal;
}

void GPUReconstructionHIPBackend::PrintKernelOccupancies()
{
  int maxBlocks = 0, threads = 0, suggestedBlocks = 0;
#define GPUCA_KRNL(x_class, x_attributes, x_arguments, x_forward) GPUCA_KRNL_WRAP(GPUCA_KRNL_LOAD_, x_class, x_attributes, x_arguments, x_forward)
#define GPUCA_KRNL_LOAD_single(x_class, x_attributes, x_arguments, x_forward)                                                         \
  GPUFailedMsg(hipOccupancyMaxPotentialBlockSize(&suggestedBlocks, &threads, GPUCA_M_CAT(krnl_, GPUCA_M_KRNL_NAME(x_class)), 0, 0));  \
  GPUFailedMsg(hipOccupancyMaxActiveBlocksPerMultiprocessor(&maxBlocks, GPUCA_M_CAT(krnl_, GPUCA_M_KRNL_NAME(x_class)), threads, 0)); \
  GPUInfo("Kernel: %50s Block size: %34d, Maximum active blocks: %3d, Suggested blocks: %3d", GPUCA_M_STR(GPUCA_M_CAT(krnl_, GPUCA_M_KRNL_NAME(x_class))), threads, maxBlocks, suggestedBlocks);
#define GPUCA_KRNL_LOAD_multi(x_class, x_attributes, x_arguments, x_forward)                                                                   \
  GPUFailedMsg(hipOccupancyMaxPotentialBlockSize(&suggestedBlocks, &threads, GPUCA_M_CAT3(krnl_, GPUCA_M_KRNL_NAME(x_class), _multi), 0, 0));  \
  GPUFailedMsg(hipOccupancyMaxActiveBlocksPerMultiprocessor(&maxBlocks, GPUCA_M_CAT3(krnl_, GPUCA_M_KRNL_NAME(x_class), _multi), threads, 0)); \
  GPUInfo("Kernel: %50s Block size: %4d, Maximum active blocks: %3d, Suggested blocks: %3d", GPUCA_M_STR(GPUCA_M_CAT3(krnl_, GPUCA_M_KRNL_NAME(x_class), _multi)), threads, maxBlocks, suggestedBlocks);
#include "GPUReconstructionKernels.h"
#undef GPUCA_KRNL
#undef GPUCA_KRNL_LOAD_single
#undef GPUCA_KRNL_LOAD_multi
}
