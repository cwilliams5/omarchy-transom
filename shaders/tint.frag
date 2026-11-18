#version 440
// Transom's icon tint (ui/AppIcon.qml): each pixel's brightness becomes a
// shade of `tint`, from `low` (darkest parts) to `high` (brightest) times the
// tint, so an icon keeps its detail but takes the tint's color. Rebuild after
// editing: qsb --qt6 -o tint.frag.qsb tint.frag (package qt6-shadertools).

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 tint;
    float low;
    float high;
};

layout(binding = 1) uniform sampler2D source;

void main() {
    vec4 color = texture(source, qt_TexCoord0);
    if (color.a <= 0.0) {
        fragColor = vec4(0.0);
        return;
    }
    vec3 straight = color.rgb / color.a;
    float luma = dot(straight, vec3(0.2126, 0.7152, 0.0722));
    vec3 shade = clamp(tint.rgb * mix(low, high, luma), 0.0, 1.0);
    fragColor = vec4(shade * color.a, color.a) * qt_Opacity;
}
