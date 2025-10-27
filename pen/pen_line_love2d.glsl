// Explicitly specify precision for all uniforms to ensure consistency across vertex and fragment shaders
extern highp vec4 u_penPoints;
extern highp vec4 u_penColor;
extern highp float u_penSize;
extern highp float u_lineLength;


const float EPSILON = 1e-3;
const float SQRT_2 = 1.4142135623730951;

vec4 position(mat4 transform_projection, vec4 vertex_position) {
    float expandedRadius = (u_penSize * 0.5) + SQRT_2;

    // Build the quad around the origin before rotating and translating.
    vec2 position = vertex_position.xy;

    position.x *= u_lineLength + (2.0 * expandedRadius);
    position.y *= 2.0 * expandedRadius;
    position -= expandedRadius;

    // Rotate quad to match pen segment direction (matches sprite.vert DRAW_MODE_line).
    vec2 pointDiff = u_penPoints.zw;
    if (abs(pointDiff.x) < EPSILON && abs(pointDiff.y) < EPSILON) {
        pointDiff.x = EPSILON;
    }
    vec2 normalized = pointDiff / max(u_lineLength, EPSILON);
    position = mat2(normalized.x, normalized.y, -normalized.y, normalized.x) * position;

    // Translate to the first pen point (already in Love canvas coordinates).
    position += u_penPoints.xy;

    return transform_projection * vec4(position, 0.0, 1.0);
}

vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
    float coverage;

    // Use built-in texture coordinates instead of custom varying
    float expandedRadius = (u_penSize * 0.5) + SQRT_2;
    vec2 penTexCoord = vec2(
        mix(0.0, u_lineLength + (expandedRadius * 2.0), texture_coords.x) - expandedRadius,
        ((texture_coords.y - 0.5) * expandedRadius) + 0.5
    );

    float d = ((penTexCoord.x - clamp(penTexCoord.x, 0.0, u_lineLength)) * 0.5) + 0.5;
    float line = distance(vec2(0.5), vec2(d, penTexCoord.y)) * 2.0;
    line -= ((u_penSize - 1.0) * 0.5);
    coverage = clamp(1.0 - line, 0.0, 1.0);
    return u_penColor * coverage;
}

