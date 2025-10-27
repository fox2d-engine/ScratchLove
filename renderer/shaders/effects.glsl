extern float fisheye;
extern float whirl;
extern float pixelate;
extern float mosaic;
extern float brightness;
extern float colorEffect;

const vec2 kCenter = vec2(0.5, 0.5);
const float kRadius = 0.5;

// Helper function to convert RGB to HSV
vec3 rgbToHsv(vec3 rgb) {
    float maxVal = max(max(rgb.r, rgb.g), rgb.b);
    float minVal = min(min(rgb.r, rgb.g), rgb.b);
    float delta = maxVal - minVal;
    
    vec3 hsv;
    hsv.z = maxVal; // Value
    
    if (maxVal == 0.0) {
        hsv.y = 0.0; // Saturation
        hsv.x = 0.0; // Hue
    } else {
        hsv.y = delta / maxVal; // Saturation
        
        if (delta == 0.0) {
            hsv.x = 0.0; // Hue
        } else if (maxVal == rgb.r) {
            hsv.x = mod((rgb.g - rgb.b) / delta, 6.0);
        } else if (maxVal == rgb.g) {
            hsv.x = (rgb.b - rgb.r) / delta + 2.0;
        } else {
            hsv.x = (rgb.r - rgb.g) / delta + 4.0;
        }
        hsv.x /= 6.0; // Normalize to [0,1]
    }
    
    return hsv;
}

// Helper function to convert HSV to RGB
vec3 hsvToRgb(vec3 hsv) {
    float h = hsv.x * 6.0;
    float s = hsv.y;
    float v = hsv.z;
    
    float c = v * s;
    float x = c * (1.0 - abs(mod(h, 2.0) - 1.0));
    float m = v - c;
    
    vec3 rgb;
    if (h < 1.0) {
        rgb = vec3(c, x, 0.0);
    } else if (h < 2.0) {
        rgb = vec3(x, c, 0.0);
    } else if (h < 3.0) {
        rgb = vec3(0.0, c, x);
    } else if (h < 4.0) {
        rgb = vec3(0.0, x, c);
    } else if (h < 5.0) {
        rgb = vec3(x, 0.0, c);
    } else {
        rgb = vec3(c, 0.0, x);
    }
    
    return rgb + vec3(m);
}

vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
    vec2 uv = texture_coords;
    
    // Apply effects in the same order as Scratch: mosaic -> pixelate -> whirl -> fisheye
    
    // Mosaic effect (applied first) - matches EffectTransform.js line 134-136
    if (mosaic != 0.0) {
        // Native Scratch: texcoord0 = fract(u_mosaic * texcoord0);
        // mosaic value is already converted by convertEffectValue to range [1, 512]
        uv = fract(uv * mosaic);
    }
    
    // Pixelate effect - matches EffectTransform.js line 138-146
    if (pixelate != 0.0) {
        // Native Scratch: texcoord0 = (floor(texcoord0 * pixelTexelSize) + kCenter) / pixelTexelSize;
        // pixelate value is already converted by convertEffectValue (abs(x)/10)
        // Note: Original uses u_skinSize / u_pixelate, we approximate with direct pixelate value
        vec2 pixelTexelSize = vec2(pixelate);
        uv = (floor(uv * pixelTexelSize) + kCenter) / pixelTexelSize;
    }
    
    // Whirl effect - matches EffectTransform.js line 148-176
    if (whirl != 0.0) {
        vec2 offset = uv - kCenter;
        float offsetMagnitude = length(offset);

        // Native Scratch: float whirlFactor = max(1.0 - (offsetMagnitude / kRadius), 0.0);
        float whirlFactor = max(1.0 - (offsetMagnitude / kRadius), 0.0);
        // Native Scratch: float whirlActual = u_whirl * whirlFactor * whirlFactor;
        // whirl value is already converted by convertEffectValue (-x * PI / 180)
        float whirlActual = whirl * whirlFactor * whirlFactor;

        float sinWhirl = sin(whirlActual);
        float cosWhirl = cos(whirlActual);

        // Apply rotation matrix (matches original)
        vec2 rotated = vec2(
            cosWhirl * offset.x + (-sinWhirl) * offset.y,
            sinWhirl * offset.x + cosWhirl * offset.y
        );

        uv = rotated + kCenter;
    }
    
    // Fisheye effect - matches EffectTransform.js line 177-191
    if (fisheye != 0.0) {
        // Native Scratch: vec2 vec = (texcoord0 - kCenter) / kCenter;
        vec2 vecOffset = (uv - kCenter) / kCenter;
        float vecLength = length(vecOffset);

        if (vecLength > 0.0) {
            // Native Scratch: float r = pow(min(vecLength, 1.0), u_fisheye) * max(1.0, vecLength);
            // fisheye value is already converted by convertEffectValue: max(0, (x + 100) / 100)
            float r = pow(min(vecLength, 1.0), fisheye) * max(1.0, vecLength);
            vec2 unit = vecOffset / vecLength;

            // Native Scratch: texcoord0 = kCenter + r * unit * kCenter;
            uv = kCenter + r * unit * kCenter;
        }
    }
    
    vec4 texelColor = Texel(texture, uv) * color;
    
    // Apply color and brightness effects - matches EffectTransform.js transformColor
    if (colorEffect != 0.0 || brightness != 0.0) {
        // Skip transparent pixels (matches line 42-44 in transformColor)
        if (texelColor.a > 0.0) {
            // Premultiply alpha division (line 60-63)
            texelColor.rgb /= texelColor.a;

            if (colorEffect != 0.0) {
                // Convert RGB to HSV
                vec3 hsv = rgbToHsv(texelColor.rgb);

                // Force slightly saturated colors for grayscale (line 69-84)
                const float minV = 0.11 / 2.0;
                const float minS = 0.09;
                if (hsv.z < minV) {
                    hsv = vec3(0.0, 1.0, minV);
                } else if (hsv.y < minS) {
                    hsv = vec3(0.0, minS, hsv.z);
                }

                // Apply hue shift (line 87-88) - colorEffect already converted by convertEffectValue
                hsv.x = mod(hsv.x + colorEffect, 1.0);

                // Convert back to RGB
                texelColor.rgb = hsvToRgb(hsv);
            }

            if (brightness != 0.0) {
                // Add brightness (line 94-101) - brightness already converted by convertEffectValue (x/100)
                texelColor.rgb = clamp(texelColor.rgb + vec3(brightness), vec3(0.0), vec3(1.0));
            }

            // Premultiply alpha again (line 105-107)
            texelColor.rgb *= texelColor.a;
        }
    }
    
    return texelColor;
}
