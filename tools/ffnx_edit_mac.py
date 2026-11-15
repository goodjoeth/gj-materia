"""macOS edits to FFNx (after tools/ffnx_edit_android.py): bgfx on Metal.

Run by tools/setup_mac.sh. Idempotent: each edit checks for its own marker.
"""
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, 'external', 'FFNx', 'src')

EDITS = [
    ('renderer.cpp',
     '''    switch (renderer_backend)
    {
    case RENDERER_BACKEND_AUTO:''',
     '''#ifdef FF7_MACOS
    return bgfx::RendererType::Metal;   // FF7Recomp macOS: Metal only
#endif
    switch (renderer_backend)
    {
    case RENDERER_BACKEND_AUTO:'''),
    ('renderer.cpp',
     '''#ifdef FFNX_ANDROID
    case bgfx::RendererType::OpenGLES:   // FF7Recomp
        currentRenderer = "OpenGL ES";
        shaderSuffix = ".gles";
        break;
#endif''',
     '''#ifdef FFNX_ANDROID
    case bgfx::RendererType::OpenGLES:   // FF7Recomp
        currentRenderer = "OpenGL ES";
        shaderSuffix = ".gles";
        break;
#endif
    case bgfx::RendererType::Metal:      // FF7Recomp macOS
        currentRenderer = "Metal";
        shaderSuffix = ".mtl";
        break;'''),
    ('renderer.cpp',
     '''    if ((bgfx::getRendererType() != bgfx::RendererType::Vulkan && bgfx::getRendererType() != bgfx::RendererType::OpenGLES) || getenv("FF7_TEST_VK_TRACE"))   // FF7Recomp''',
     '''    if ((bgfx::getRendererType() != bgfx::RendererType::Vulkan && bgfx::getRendererType() != bgfx::RendererType::OpenGLES && bgfx::getRendererType() != bgfx::RendererType::Metal) || getenv("FF7_TEST_VK_TRACE"))   // FF7Recomp'''),
    ('renderer.cpp',
     '''        if (bgfx::getRendererType() != bgfx::RendererType::Vulkan && bgfx::getRendererType() != bgfx::RendererType::OpenGLES)
        {''',
     '''        if (bgfx::getRendererType() != bgfx::RendererType::Vulkan && bgfx::getRendererType() != bgfx::RendererType::OpenGLES && bgfx::getRendererType() != bgfx::RendererType::Metal)
        {'''),
]

# FFNx defines globals in headers and links with /FORCE:MULTIPLE (lld: --allow-multiple-definition);
# Apple's linker has no such option, so these become C++17 inline definitions (one shared copy).
INLINE = [
    ('input.h', 'std::vector<MouseListener*> mouseListeners;', 'inline std::vector<MouseListener*> mouseListeners;'),
    ('input.h', 'std::vector<KeyListener*> keyListeners;', 'inline std::vector<KeyListener*> keyListeners;'),
    ('widescreen.h', 'int wide_game_x = 0;', 'inline int wide_game_x = 0;'),
    ('widescreen.h', 'int wide_game_y = 0;', 'inline int wide_game_y = 0;'),
    ('widescreen.h', 'int wide_game_width = 854;', 'inline int wide_game_width = 854;'),
    ('widescreen.h', 'int wide_game_height = 480;', 'inline int wide_game_height = 480;'),
    ('ff7/world/utils.h', '    bool is_key_pressed(int', '    inline bool is_key_pressed(int'),
    ('ff7/world/utils.h', '    bool is_key_pressed_first_time(', '    inline bool is_key_pressed_first_time('),
    ('ff7/world/utils.h', '    bool is_key_released(', '    inline bool is_key_released('),
    ('ff7/field/opcode.h', '    std::array<uint32_t, 256> original_opcode_table {0};', '    inline std::array<uint32_t, 256> original_opcode_table {0};'),
    ('ff7/field/model.h', '    uint32_t ff7_kawai_current_model_id = 0xFF;', '    inline uint32_t ff7_kawai_current_model_id = 0xFF;'),
    ('ff7/field/model.h', '    std::array<external_field_model_data, MAX_FIELD_MODELS> external_model_data;', '    inline std::array<external_field_model_data, MAX_FIELD_MODELS> external_model_data;'),
    ('ff7/field/background.h', '    vector2<float>\n        field_curr_delta_world_pos,', '    inline vector2<float>\n        field_curr_delta_world_pos,'),
    ('movies.h', 'extern short movie_fps_ratio = 1;', 'inline short movie_fps_ratio = 1;'),
    ('movies.h', 'extern bool is_movie_bgfield = false;', 'inline bool is_movie_bgfield = false;'),
    ('ff8/file.h', 'uint32_t(*ff8_read_file)(uint32_t count', 'inline uint32_t(*ff8_read_file)(uint32_t count'),
    ('ff8/file.h', 'void (*ff8_close_file)(struct ff8_file* file);', 'inline void (*ff8_close_file)(struct ff8_file* file);'),
    ('../../deps/openpsf/include/openpsf/openpsf.h', 'PsfFlags operator|(PsfFlags flags, PsfFlags other) noexcept {', 'inline PsfFlags operator|(PsfFlags flags, PsfFlags other) noexcept {'),
]
EDITS += INLINE

# The window resized (live resize, full screen): FFNx's WM_SIZE path (common.cpp) for the macOS
# window -- new output size, view offsets from scratch, framebuffers and swap chain rebuilt.
EDITS.append(('renderer.cpp',
'''        bgfxInit.swapChain.nwh = nwh;
        bgfx::reset(bgfxInit.reset, &bgfxInit.swapChain);
    }
#endif''',
'''        bgfxInit.swapChain.nwh = nwh;
        bgfx::reset(bgfxInit.reset, &bgfxInit.swapChain);
    }
#endif
#ifdef FF7_MACOS
    {   // FF7Recomp macOS: follow the window's size
        int w = 0, h = 0;
        ff7_platform_window(&w, &h);
        if (w > 0 && h > 0 && (w != (int)window_size_x || h != (int)window_size_y))
        {
            window_size_x = w;
            window_size_y = h;
            viewOffsetX = viewOffsetY = 0;
            x_offset = y_offset = 0;
            reset();
        }
    }
#endif'''))

# FF7Recomp: a 21:9 mode (aspect_ratio = 4), the way FFNx does 16:10: the widescreen viewport is
# 1138x480 (64:27, 2560x1080 and 3440x1440 screens) instead of 854x480; every widescreen patch
# reads wide_viewport_x / wide_viewport_width, so fields with room, battles, the world map and
# the menus widen with it. Fields narrower than that keep their bars, as they do at 16:9.
EDITS.extend([
('common.h',
'''	AR_WIDESCREEN_16X10,
	AR_COUNT''',
'''	AR_WIDESCREEN_16X10,
	AR_WIDESCREEN_21X9,   // FF7Recomp
	AR_COUNT'''),
('common.cpp',
'''		widescreen_enabled = (aspect_ratio == AR_WIDESCREEN_16X9 || aspect_ratio == AR_WIDESCREEN_16X10);''',
'''		widescreen_enabled = (aspect_ratio == AR_WIDESCREEN_16X9 || aspect_ratio == AR_WIDESCREEN_16X10 || aspect_ratio == AR_WIDESCREEN_21X9);'''),
('ff7/widescreen.cpp',
'''        viewport_width_plus_x_widescreen_fix = 704;
    }''',
'''        viewport_width_plus_x_widescreen_fix = 704;
    }
    else if (aspect_ratio == AR_WIDESCREEN_21X9)   // FF7Recomp
    {
        wide_viewport_x = -249;
        wide_viewport_width = 1138;
        wide_game_width = 1138;
        viewport_width_plus_x_widescreen_fix = 892;
    }'''),
('renderer.cpp',
'''        case AR_WIDESCREEN_16X10:''',
'''        case AR_WIDESCREEN_21X9:   // FF7Recomp: as 16:9, at the viewport's own ratio
            if (viewWidth * wide_game_height != viewHeight * wide_game_width)
            {
                if (viewHeight * wide_game_width > viewWidth * wide_game_height)
                {
                    viewOffsetY = (viewHeight - (viewWidth * wide_game_height) / wide_game_width) / 2;
                    viewHeight = (viewWidth * wide_game_height) / wide_game_width;
                    y_offset = viewOffsetY;
                }
                else
                {
                    viewOffsetX = (viewWidth - (viewHeight * wide_game_width) / wide_game_height) / 2;
                    viewWidth = (viewHeight * wide_game_width) / wide_game_height;
                    x_offset = viewOffsetX;
                }
            }
            break;
        case AR_WIDESCREEN_16X10:'''),
('gl/special_case.cpp',
'''16 / (aspect_ratio == AR_WIDESCREEN_16X10 ? 10.f : 9.f)''',
'''(aspect_ratio == AR_WIDESCREEN_21X9 ? (float)wide_game_width / wide_game_height : 16 / (aspect_ratio == AR_WIDESCREEN_16X10 ? 10.f : 9.f))'''),
])

# 21:9 fields: the camera clamp's half extension (53 = 107 / 2 at 16:9) follows the viewport, and a
# field wide enough for 16:9 but not for 21:9 still extends -- centred, as far as its background
# goes -- instead of dropping to 4:3.
EDITS.append(('ff7/field/background.cpp', 'std::min(53, cameraRangeSize / 2 - 160)',
              'std::min(aspect_ratio == AR_WIDESCREEN_21X9 ? abs(wide_viewport_x) / 2 : 53, cameraRangeSize / 2 - 160)', 'all'))
EDITS.append(('ff7/widescreen.cpp',
'''    if(camera_range.right - camera_range.left >= game_width / 2 + abs(wide_viewport_x))''',
'''    if(camera_range.right - camera_range.left >= game_width / 2 + (aspect_ratio == AR_WIDESCREEN_21X9 ? 107 : abs(wide_viewport_x)))   // FF7Recomp: 21:9'''))

# 21:9 world map: the clouds-and-sky quad is +-256 (enough for 16:9's half width of 213); at
# 21:9 the half width is 284, so it follows the skybox's own margin (width / 4 + 20).
EDITS.append(('ff7/widescreen.cpp',
'''    patch_code_short(ff7_externals.world_submit_draw_clouds_and_meteor_7547A6 + 0x132, -256);
    patch_code_int(ff7_externals.world_submit_draw_clouds_and_meteor_7547A6 + 0x144, 256);
    patch_code_byte(ff7_externals.world_submit_draw_clouds_and_meteor_7547A6 + 0x15C, 0);
    patch_code_short(ff7_externals.world_submit_draw_clouds_and_meteor_7547A6 + 0x16D, 256);''',
'''    const int clouds_half = aspect_ratio == AR_WIDESCREEN_21X9 ? wide_viewport_width / 4 + 20 : 256;   // FF7Recomp: 21:9
    patch_code_short(ff7_externals.world_submit_draw_clouds_and_meteor_7547A6 + 0x132, -clouds_half);
    patch_code_int(ff7_externals.world_submit_draw_clouds_and_meteor_7547A6 + 0x144, clouds_half);
    patch_code_byte(ff7_externals.world_submit_draw_clouds_and_meteor_7547A6 + 0x15C, 0);
    patch_code_short(ff7_externals.world_submit_draw_clouds_and_meteor_7547A6 + 0x16D, clouds_half);'''))

# The widescreen code patches (ff7_widescreen_hook_init, at driver start) bake values like the
# skybox's width / 4 + 20 into the game's code before Widescreen::init sets the 21:9 viewport:
# set it here first.
EDITS.append(('ff7/widescreen.cpp',
'''void ff7_widescreen_hook_init() {
    // Field fix''',
'''void ff7_widescreen_hook_init() {
    if (aspect_ratio == AR_WIDESCREEN_21X9)   // FF7Recomp: as Widescreen::init, before the patches below
    {
        wide_viewport_x = -249;
        wide_viewport_width = 1138;
        wide_game_width = 1138;
        viewport_width_plus_x_widescreen_fix = 892;
    }
    // Field fix'''))


def main():
    n = 0
    for name, old, new, *how in EDITS:
        p = os.path.normpath(os.path.join(SRC, name))
        old, new = old.replace('\\n', '\n'), new.replace('\\n', '\n')
        s = open(p, encoding='utf-8', errors='surrogateescape').read()
        if new in s:
            continue
        if old not in s:
            sys.exit(f'ffnx_edit_mac: anchor not found in {name}:\n{old[:120]}')
        s = s.replace(old, new) if how == ['all'] else s.replace(old, new, 1)
        open(p, 'w', encoding='utf-8', errors='surrogateescape').write(s)
        n += 1
    print(f'ffnx_edit_mac: {n} edits applied')


if __name__ == '__main__':
    main()
