package main

import "core:runtime";
import "core:os"
import "core:fmt";

import sg "third_party/sokol_gfx"
import sapp "third_party/sokol_app"

when ODIN_OS == .Windows {
    import win32 "core:sys/windows"
}

state: struct {
    pass_action: sg.Pass_Action,
    bind:        sg.Bindings,
    pip:         sg.Pipeline,
    fullscreen:  bool,
};

app_init :: proc "c" () {
    context = runtime.default_context();
    sg.setup({
        mtl_device                   = sapp.metal_get_device(),
        mtl_renderpass_descriptor_cb = sapp.metal_get_renderpass_descriptor,
        mtl_drawable_cb              = sapp.metal_get_drawable,
        d3d11_device                 = sapp.d3d11_get_device(),
        d3d11_device_context         = sapp.d3d11_get_device_context(),
        d3d11_render_target_view_cb  = sapp.d3d11_get_render_target_view,
        d3d11_depth_stencil_view_cb  = sapp.d3d11_get_depth_stencil_view,
    });

    Vertex :: struct {
        pos: [3]f32,
        col: [4]f32,
    };

    vertices := [?]Vertex{
        {{+0.5, +0.5, +0.5}, {1.0, 0.0, 0.0, 1.0}},
        {{+0.5, -0.5, +0.5}, {0.0, 1.0, 0.0, 1.0}},
        {{-0.5, -0.5, +0.5}, {0.0, 0.0, 1.0, 1.0}},
        {{-0.5, -0.5, +0.5}, {0.0, 0.0, 1.0, 1.0}},
        {{-0.5, +0.5, +0.5}, {0.0, 0.0, 1.0, 1.0}},
        {{+0.5, +0.5, +0.5}, {1.0, 0.0, 0.0, 1.0}},
    };
    state.bind.vertex_buffers[0] = sg.make_buffer({
        size = len(vertices)*size_of(vertices[0]),
        content = &vertices[0],
        label = "triangle-vertices",
    });

    vs_source, fs_source: cstring;
    #partial switch sg.query_backend() {
        case .D3D11: {
            vs_source = `
                struct vs_in {
                    float4 pos: POS;
                    float4 col: COLOR;
                };
                struct vs_out {
                    float4 col: COLOR0;
                    float4 pos: SV_POSITION;
                };
                vs_out main(vs_in inp) {
                    vs_out outp;
                    outp.pos = inp.pos;
                    outp.col = inp.col;
                    return outp;
                }
            `;
            fs_source = `
                float4 main(float4 col: COLOR0): SV_TARGET0 {
                    return col;
                }
            `;
        }
        case .METAL_MACOS: {
            vs_source = `
                #include <metal_stdlib>
                using namespace metal;
                struct vs_in {
                    float4 position [[attribute(0)]];
                    float4 color [[attribute(1)]];
                };
                struct vs_out {
                    float4 position [[position]];
                    float4 color;
                };
                vertex vs_out _main(vs_in inp [[stage_in]]) {
                    vs_out outp;
                    outp.position = inp.position;
                    outp.color = inp.color;
                    return outp;
                }
            `;
            fs_source = `
                #include <metal_stdlib>
                using namespace metal;
                fragment float4 _main(float4 color [[stage_in]]) {
                    return color;
                }
            `;
        }
    }
    state.pip = sg.make_pipeline({
        shader = sg.make_shader({
            vs = {source = vs_source},
            fs = {source = fs_source},
            attrs = {
                0 = {sem_name = "POS"},
                1 = {sem_name = "COLOR"},
            },
        }),
        label = "triangle-pipeline",
        primitive_type = .TRIANGLES,
        layout = {
            attrs = {
                0 = {format = .FLOAT3},
                1 = {format = .FLOAT4},
            },
        },
    });

    state.pass_action.colors[0] = {action = .CLEAR, val = {0.5, 0.7, 1.0, 1}};
}

app_frame :: proc "c" () {
    context = runtime.default_context();
    sg.begin_default_pass(state.pass_action, sapp.framebuffer_size());
    sg.apply_pipeline(state.pip);
    sg.apply_bindings(state.bind);
    sg.draw(0, 3, 1);
    sg.end_pass();
    sg.commit();
}

app_destroy :: proc "c" () {
    sg.shutdown();
}

main :: proc() {
    err := sapp.run({
        init_cb      = app_init,
        frame_cb     = app_frame,
        cleanup_cb   = app_destroy,
        event_cb     = app_event,
        width        = 800,
        height       = 600,
        window_title = "SOKOL Quad",
        fullscreen   = state.fullscreen,
        sample_count = 4,
    });
    os.exit(int(err));
}

when ODIN_OS == .Windows {
    win32_toggle_fullscreen :: proc "c" (hwnd: win32.HWND, fullscreen: bool) {
        @static placement : win32.WINDOWPLACEMENT;

        style := win32.GetWindowLongW(hwnd, win32.GWL_STYLE)

        if (fullscreen)
        {
            monitor : win32.MONITORINFO = {};
            monitor.cbSize = size_of(win32.MONITORINFO);

            if (
                win32.GetWindowPlacement(hwnd, &placement) &&
                win32.GetMonitorInfoW(win32.MonitorFromWindow(hwnd, win32.Monitor_From_Flags.MONITOR_DEFAULTTOPRIMARY), &monitor)
            )
            {
                win32.SetWindowLongW(hwnd, win32.GWL_STYLE, style & ~cast(i32)win32.WS_OVERLAPPEDWINDOW);
                win32.SetWindowPos(
                    hwnd,
                    win32.HWND_TOP,
                    monitor.rcMonitor.left,
                    monitor.rcMonitor.top,
                    monitor.rcMonitor.right  - monitor.rcMonitor.left,
                    monitor.rcMonitor.bottom - monitor.rcMonitor.top,
                    win32.SWP_NOOWNERZORDER | win32.SWP_FRAMECHANGED
                );
            }
        }
        else
        {
            win32.SetWindowLongW(hwnd, win32.GWL_STYLE, style | cast(i32)win32.WS_OVERLAPPEDWINDOW);
            win32.SetWindowPlacement(hwnd, &placement);
            flags: win32.DWORD = win32.SWP_NOMOVE | win32.SWP_NOSIZE | win32.SWP_NOZORDER | win32.SWP_NOOWNERZORDER | win32.SWP_FRAMECHANGED;
            win32.SetWindowPos(hwnd, nil, 0, 0, 0, 0, flags);
        }
    }
}

app_event :: proc "c" (event: ^sapp.Event) {
    if event.type == .KEY_DOWN && !event.key_repeat {
        #partial switch event.key_code {
        case .ESCAPE:
            sapp.request_quit();
        case .Q:
            if .CTRL in event.modifiers {
                sapp.request_quit();
            }
        case .F11:
            when ODIN_OS == .Windows {
                hwnd := cast(win32.HWND)sapp.win32_get_hwnd();
                state.fullscreen = !state.fullscreen;
                win32_toggle_fullscreen(hwnd, state.fullscreen);
            }
        }
    }
}
