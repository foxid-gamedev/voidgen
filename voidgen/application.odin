package voidgen

//*****************************************************************************//

// core libraries
import "core:fmt"
import "core:log"
import "base:runtime"
import "core:strings"

// vendor libraries
import "vendor:glfw"
import vk "vendor:vulkan"

//*****************************************************************************//

// structs
Application :: struct {
    ctx: runtime.Context,
    window_handle: glfw.WindowHandle,
    instance: vk.Instance,
    debug_utils_messenger: vk.DebugUtilsMessengerEXT,
    physical_device: vk.PhysicalDevice,
    device: vk.Device,
    graphics_queue: vk.Queue,

    queue_family_indices: struct {
        graphics: Maybe(u32),
    }
}

// constants
VG_INIT_SCR_WIDTH :: 1920
VG_INIT_SCR_HEIGHT :: 1080
VG_SCR_TITLE :: "Voidgen Hello Triangle"

// global data
g : Application

g_validation_layers : []cstring = {
    "VK_LAYER_KHRONOS_validation",
}

//*****************************************************************************//
// application function
//*****************************************************************************//
start_application :: proc() {
    // setup logging
    context.logger = log.create_console_logger()
    context.logger.options = {.Terminal_Color}
    g.ctx = context

    // glfw
    glfw_init(); defer glfw_destroy()

    // vulkan 
    instance_init(); defer instance_destroy()
    pick_physical_device()
    device_create(); defer device_destroy()


    // loop
    for !glfw.WindowShouldClose(g.window_handle) {
        free_all(g.ctx.temp_allocator)
        glfw.PollEvents()
    }
}

//*****************************************************************************//
// setup glfw app & window 
//*****************************************************************************//
glfw_init :: proc() {
    if glfw.Init() != glfw.TRUE {
        panic("glfw initializiation failed")
    }

    glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
    glfw.WindowHint(glfw.RESIZABLE, glfw.FALSE)

    g.window_handle = glfw.CreateWindow(
        VG_INIT_SCR_WIDTH, 
        VG_INIT_SCR_HEIGHT, 
        VG_SCR_TITLE, 
        nil, 
        nil
    )
    if (g.window_handle == nil) {
        panic("glfw window creation failed")
    }
}

glfw_destroy :: proc() {
    glfw.DestroyWindow(g.window_handle)
    glfw.Terminate()
}

//*****************************************************************************//
// create an vulkan instance & debugging
//*****************************************************************************//
instance_init :: proc() {
    vk.load_proc_addresses_global(rawptr(glfw.GetInstanceProcAddress))
    
    extenseions := []cstring {
        vk.EXT_DEBUG_UTILS_EXTENSION_NAME,
        vk.KHR_SURFACE_EXTENSION_NAME,
    }

    instance_create_info : vk.InstanceCreateInfo = {
        sType = .INSTANCE_CREATE_INFO,
        pApplicationInfo = &{
            sType = .APPLICATION_INFO,
            pApplicationName = "Voidgen",
            applicationVersion = vk.MAKE_VERSION(1,0,0),
            pEngineName = "Voidgen",
            engineVersion = vk.MAKE_VERSION(1,0,0),
            apiVersion = vk.API_VERSION_1_3,
        },
        enabledLayerCount = u32(len(g_validation_layers)),
        ppEnabledLayerNames = raw_data(g_validation_layers),
        enabledExtensionCount = u32(len(extenseions)),
        ppEnabledExtensionNames = raw_data(extenseions),
    }

when ODIN_DEBUG {
    debug_util_create_info : vk.DebugUtilsMessengerCreateInfoEXT = {
        sType = .DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
        messageType = {.VALIDATION, .PERFORMANCE},
        messageSeverity = {.ERROR, .WARNING, .INFO},
        pfnUserCallback = proc "system" (
            messageSeverity: vk.DebugUtilsMessageSeverityFlagsEXT, 
            messageTypes: vk.DebugUtilsMessageTypeFlagsEXT, 
            pCallbackData: ^vk.DebugUtilsMessengerCallbackDataEXT, 
            pUserData: rawptr) -> b32 {
                level : log.Level
                context = g.ctx
                if .ERROR in messageSeverity {
                    level = .Error
                } else if .WARNING in messageSeverity {
                    level = .Warning
                } else if .INFO in messageSeverity {
                    level = .Info
                } else {
                    level = .Debug
                }

                log.log(level, pCallbackData.pMessage)
                return false
        },
    }

    instance_create_info.pNext = &debug_util_create_info
}

    vk_check(vk.CreateInstance(&instance_create_info, nil, &g.instance))

    vk.load_proc_addresses_instance(g.instance)

when ODIN_DEBUG {
    vk_check(vk.CreateDebugUtilsMessengerEXT(
        g.instance, 
        &debug_util_create_info, 
        nil, 
        &g.debug_utils_messenger
    ))
}

}

//*****************************************************************************//
// destroy the vulkan instance
//*****************************************************************************//
instance_destroy :: proc() {
    vk.DestroyDebugUtilsMessengerEXT(g.instance, g.debug_utils_messenger, nil)
    vk.DestroyInstance(g.instance, nil)
}

//*****************************************************************************//
// pick a physical device
//*****************************************************************************//
pick_physical_device :: proc() {
    device_count : u32
    vk_check(vk.EnumeratePhysicalDevices(g.instance, &device_count, nil))
    log.assert(device_count > 0, "vulkan: no physical device found!")

    devices := make([dynamic]vk.PhysicalDevice, int(device_count))
    vk_check(vk.EnumeratePhysicalDevices(
        g.instance, 
        &device_count, 
        raw_data(devices)
    ))

    device_index : int = -1
    for device, i in devices {
        graphics_index, is_suitable := is_device_suitable(device)

        if is_suitable && graphics_index >= 0 {
            g.physical_device = device
            g.queue_family_indices.graphics = u32(graphics_index)
            device_index = i
            break
        }
    }

    log.assert(g.physical_device != nil, "vulkan: couldn't pick a physical device!")

    properties := make([dynamic]vk.PhysicalDeviceProperties, int(device_count))
    vk.GetPhysicalDeviceProperties(g.physical_device, raw_data(properties))

    log.log(.Info, "Vulkan: picked physical device:", strings.clone_from_bytes(properties[device_index].deviceName[:], g.ctx.temp_allocator))
}

//*****************************************************************************//
// checks whether a device is suitable
//*****************************************************************************//
is_device_suitable :: proc(device: vk.PhysicalDevice) -> (queue_family_index: i32,suitable: bool) {
    queue_family_count : u32

    vk.GetPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, nil)

    queue_families := make([dynamic]vk.QueueFamilyProperties, int(queue_family_count))
    vk.GetPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, raw_data(queue_families))

    for queue_family, i in queue_families {
        if .GRAPHICS in queue_family.queueFlags {
            return i32(i),true
        }
    }

    return i32(-1),false
}

//*****************************************************************************//
// create a logical device
//*****************************************************************************//
device_create :: proc() {
    queue_priority : f32 = 1.0

    queue_create_info : vk.DeviceQueueCreateInfo = {
        sType = .DEVICE_QUEUE_CREATE_INFO,
        queueFamilyIndex = g.queue_family_indices.graphics.(u32),
        queueCount = 1,
        pQueuePriorities = &queue_priority,
    }

    device_features : vk.PhysicalDeviceFeatures

    device_create_info : vk.DeviceCreateInfo = {
        sType = .DEVICE_CREATE_INFO,
        pQueueCreateInfos = &queue_create_info,
        queueCreateInfoCount = 1,
        pEnabledFeatures = &device_features,
    }

when ODIN_DEBUG {
    device_create_info.enabledLayerCount = u32(len(g_validation_layers))
    device_create_info.ppEnabledLayerNames = raw_data(g_validation_layers)
}

    vk_check(vk.CreateDevice(g.physical_device, &device_create_info, nil, &g.device))
    vk.GetDeviceQueue(g.device, g.queue_family_indices.graphics.(u32), 0, &g.graphics_queue)
}

//*****************************************************************************//
// destroy the logical device
//*****************************************************************************//
device_destroy :: proc() {
    vk.DestroyDevice(g.device, nil)
}

//*****************************************************************************//
// panics if a vulkan function did not succeeded
//*****************************************************************************//
vk_check :: proc(result: vk.Result) {
    if result != .SUCCESS {
        fmt.panicf("vulkan error: {}", result)
    }
}