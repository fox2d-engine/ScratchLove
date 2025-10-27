--- Resvg FFI C definitions
--- This file contains all required C functions and structure definitions for the resvg library
--- @module 'ffi_defs'

local ffi = require("ffi")

ffi.cdef [[
    // Version information
    static const int RESVG_MAJOR_VERSION = 0;
    static const int RESVG_MINOR_VERSION = 45;
    static const int RESVG_PATCH_VERSION = 1;

    // List of possible errors
    typedef enum {
        RESVG_OK = 0,                           // Everything is ok
        RESVG_ERROR_NOT_AN_UTF8_STR,            // Only UTF-8 content is supported
        RESVG_ERROR_FILE_OPEN_FAILED,           // Failed to open the provided file
        RESVG_ERROR_MALFORMED_GZIP,             // Compressed SVG must use the GZip algorithm
        RESVG_ERROR_ELEMENTS_LIMIT_REACHED,     // SVG has more than 1_000_000 elements (security limit)
        RESVG_ERROR_INVALID_SIZE,               // SVG has invalid size (width/height <= 0 or missing viewBox)
        RESVG_ERROR_PARSING_FAILED,             // Failed to parse SVG data
    } resvg_error;

    // Image rendering method
    typedef enum {
        RESVG_IMAGE_RENDERING_OPTIMIZE_QUALITY,
        RESVG_IMAGE_RENDERING_OPTIMIZE_SPEED,
    } resvg_image_rendering;

    typedef enum {
        RESVG_SHAPE_RENDERING_OPTIMIZE_SPEED,
        RESVG_SHAPE_RENDERING_CRISP_EDGES,
        RESVG_SHAPE_RENDERING_GEOMETRIC_PRECISION,
    } resvg_shape_rendering;

    typedef enum {
        RESVG_TEXT_RENDERING_OPTIMIZE_SPEED,
        RESVG_TEXT_RENDERING_OPTIMIZE_LEGIBILITY,
        RESVG_TEXT_RENDERING_GEOMETRIC_PRECISION,
    } resvg_text_rendering;

    // Basic structures
    // A 2D transform representation (affine transformation matrix)
    typedef struct {
        float a;  // Horizontal scaling / cosine of rotation angle
        float b;  // Vertical skewing / sine of rotation angle
        float c;  // Horizontal skewing / negative sine of rotation angle
        float d;  // Vertical scaling / cosine of rotation angle
        float e;  // Horizontal translation
        float f;  // Vertical translation
    } resvg_transform;

    // A size representation
    typedef struct {
        float width;   // Width in pixels
        float height;  // Height in pixels
    } resvg_size;

    // A rectangle representation
    typedef struct {
        float x;       // X coordinate of the top-left corner
        float y;       // Y coordinate of the top-left corner
        float width;   // Rectangle width
        float height;  // Rectangle height
    } resvg_rect;

    // Opaque pointer types
    // An SVG to resvg_render_tree conversion options
    // Contains a fonts database used during text to path conversion
    // The database is empty by default
    typedef struct resvg_options resvg_options;
    
    // An opaque pointer to the rendering tree
    typedef struct resvg_render_tree resvg_render_tree;

    // Global functions
    resvg_transform resvg_transform_identity(void);
    void resvg_init_log(void);

    // Options related functions
    resvg_options* resvg_options_create(void);
    void resvg_options_destroy(resvg_options *opt);
    void resvg_options_set_resources_dir(resvg_options *opt, const char *path);
    void resvg_options_set_dpi(resvg_options *opt, float dpi);
    void resvg_options_set_stylesheet(resvg_options *opt, const char *content);
    void resvg_options_set_font_family(resvg_options *opt, const char *family);
    void resvg_options_set_font_size(resvg_options *opt, float size);
    void resvg_options_set_serif_family(resvg_options *opt, const char *family);
    void resvg_options_set_sans_serif_family(resvg_options *opt, const char *family);
    void resvg_options_set_cursive_family(resvg_options *opt, const char *family);
    void resvg_options_set_fantasy_family(resvg_options *opt, const char *family);
    void resvg_options_set_monospace_family(resvg_options *opt, const char *family);
    void resvg_options_set_languages(resvg_options *opt, const char *languages);
    void resvg_options_set_shape_rendering_mode(resvg_options *opt, resvg_shape_rendering mode);
    void resvg_options_set_text_rendering_mode(resvg_options *opt, resvg_text_rendering mode);
    void resvg_options_set_image_rendering_mode(resvg_options *opt, resvg_image_rendering mode);
    void resvg_options_load_font_data(resvg_options *opt, const char *data, uintptr_t len);
    int32_t resvg_options_load_font_file(resvg_options *opt, const char *file_path);
    void resvg_options_load_system_fonts(resvg_options *opt);

    // Tree related functions
    int32_t resvg_parse_tree_from_file(const char *file_path,
                                       const resvg_options *opt,
                                       resvg_render_tree **tree);
    int32_t resvg_parse_tree_from_data(const char *data,
                                       uintptr_t len,
                                       const resvg_options *opt,
                                       resvg_render_tree **tree);
    void resvg_tree_destroy(resvg_render_tree *tree);
    bool resvg_is_image_empty(const resvg_render_tree *tree);
    resvg_size resvg_get_image_size(const resvg_render_tree *tree);
    bool resvg_get_object_bbox(const resvg_render_tree *tree, resvg_rect *bbox);
    bool resvg_get_image_bbox(const resvg_render_tree *tree, resvg_rect *bbox);

    // Node operation functions
    bool resvg_node_exists(const resvg_render_tree *tree, const char *id);
    bool resvg_get_node_transform(const resvg_render_tree *tree,
                                  const char *id,
                                  resvg_transform *transform);
    bool resvg_get_node_bbox(const resvg_render_tree *tree,
                             const char *id,
                             resvg_rect *bbox);
    bool resvg_get_node_stroke_bbox(const resvg_render_tree *tree,
                                    const char *id,
                                    resvg_rect *bbox);

    // Rendering functions
    void resvg_render(const resvg_render_tree *tree,
                     resvg_transform transform,
                     uint32_t width,
                     uint32_t height,
                     char *pixmap);
    bool resvg_render_node(const resvg_render_tree *tree,
                          const char *id,
                          resvg_transform transform,
                          uint32_t width,
                          uint32_t height,
                          char *pixmap);
]]

return ffi
