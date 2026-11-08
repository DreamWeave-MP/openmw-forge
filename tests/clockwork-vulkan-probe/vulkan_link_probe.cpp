#define VMA_IMPLEMENTATION
#include <vk_mem_alloc.h>

int main()
{
    VkInstanceCreateInfo createInfo{};
    createInfo.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
    VkInstance instance = VK_NULL_HANDLE;
    return vkCreateInstance(&createInfo, nullptr, &instance) == VK_SUCCESS ? 0 : 1;
}
