// fragment shader for rendering RD effect
precision mediump float;

uniform sampler2D u_grayscott;
uniform vec2 u_resolution;
uniform float u_fadein;


vec2 deserialize(vec4 v) {
    ivec4 as_ints = ivec4(v * float(0xFF));
    return vec2(float(as_ints.r*0xFF + as_ints.g) / 65535.0,
                float(as_ints.b*0xFF + as_ints.a) / 65535.0);
}

void main() {
    float fade = u_fadein;
    vec2 offset = abs(gl_FragCoord.xy - (u_resolution * vec2(0.5, 1.0)));

    // figure out which box border we're furthest from, and how far we are from it
    float dist = (420.0 + 102.0 * u_fadein) - offset.x;  // side borders
    dist = min(dist, (539.0 + 136.0 * u_fadein) - offset.y);  // lower border
    dist = min(dist, (-27.0 + 102.0 * u_fadein) + offset.y);  // upper border

    if (dist > fade) {
        // fade out near the edges of the box (margin width: 17 pixels)
        fade = dist > 17.0 ? 1.0 : max(fade, dist / 17.0);
    }

    vec2 pos = mod(gl_FragCoord.xy - mod(u_resolution*vec2(0.0, 1.0), 320.0), 320.0)/320.0;
    vec2 ab = deserialize(texture2D(u_grayscott, pos));
    float noise = ab.x;
    vec3 c;
    if (noise < (1.0-fade)) {
        c = vec3(0);
    } else {
        vec3 c1 = vec3(1.2*noise*(1.0-noise)*(1.0-noise), noise*0.85, noise*1.05);
        vec3 c2 = vec3(0.6+(0.34*noise));
        c = fade*(c1*(1.0-u_fadein) + c2*u_fadein);
    }
    gl_FragColor = vec4(c, 1);
}