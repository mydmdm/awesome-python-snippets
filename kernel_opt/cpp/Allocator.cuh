#ifndef __ALLOCATOR_CUH__
#define __ALLOCATOR_CUH__

#include "utils.h"

#include <cuda_runtime.h>
#include <stdexcept>

inline void check_cuda(cudaError_t result, const char *msg = nullptr)
{
    if (result != cudaSuccess)
    {
        if (msg)
        {
            throw std::runtime_error(msg);
        }
        else
        {
            throw std::runtime_error("operation failed");
        }
    }
}

template <typename T>
struct Array_
{
    bool _is_device{false};
    T *_start{nullptr};
    T *_end{nullptr};
};

template <typename T>
inline int len(Array_<T> *obj)
{
    return obj->_end - obj->_start;
}

using fn_allocate_t = cudaError_t (*)(void **, size_t);
using fn_free_t = cudaError_t (*)(void *);

template <typename T>
struct Allocator_
{
    fn_allocate_t _allocate_fn;
    fn_free_t _free_fn;
    bool _is_device;
    Allocator_(fn_allocate_t f1, fn_free_t f2, bool flag) : _allocate_fn(f1), _free_fn(f2), _is_device(flag) {}

    void allocate(size_t size, Array_<T> *obj)
    {
        auto result = this->_allocate_fn((void **)&obj->_start, size * sizeof(T));
        check_cuda(result);
        obj->_end = obj->_start + size;
        obj->_is_device = this->_is_device;
    }
    void deallocate(Array_<T> *obj)
    {
        if (obj->_start)
        {
            auto result = this->_free_fn(obj->_start);
            check_cuda(result);
            obj->_start = obj->_end = nullptr;
        }
    }
};

cudaError_t malloc_naive(void **ptr, size_t bytes)
{
    *ptr = malloc(bytes);
    return cudaSuccess;
}

template <typename T>
struct NaiveHostAllocator : public Allocator_<T>
{
    NaiveHostAllocator() : Allocator_<T>(malloc_naive, free, false) {}
};

template <typename T>
struct PinnedHostAllocator : public Allocator_<T>
{
    PinnedHostAllocator() : Allocator_<T>(cudaMallocHost, cudaFreeHost, false) {}
};

template <typename T>
struct DeviceAllocator : public Allocator_<T>
{
    DeviceAllocator() : Allocator_<T>(cudaMalloc, cudaFree, true) {}
};

template <typename T>
cudaError_t copy_memory(Array_<T> *dst, Array_<T> *src)
{
    auto bytes = len(src) * sizeof(T);
    if (!dst->_is_device && !src->_is_device) // from host to host
    {
        memcpy(dst->_start, src->_start, bytes);
        return cudaSuccess;
    }
    if (dst->_is_device && !src->_is_device) // from host to device
    {
        return cudaMemcpy(dst->_start, src->_start, bytes, cudaMemcpyHostToDevice);
    }
    if (!dst->_is_device && src->_is_device) // from device to host
    {
        return cudaMemcpy(dst->_start, src->_start, bytes, cudaMemcpyDeviceToHost);
    }
    assert_true(false, "NotImplemented");
}

#endif /* __ALLOCATOR_CUH__ */
