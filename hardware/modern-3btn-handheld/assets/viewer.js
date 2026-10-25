/* GenThang modern build guide: a small WebGL2 product renderer for the CAD parts in models.js.
   Coordinates are the CAD's: x right, y up the case, z out of the face (mm). z is "up" in the scene. */
(function () {
  'use strict';

  // ---------- tiny matrix helpers (column-major, like GLSL) ----------
  const M4 = {
    mul(a, b) {
      const o = new Float32Array(16);
      for (let c = 0; c < 4; c++) for (let r = 0; r < 4; r++) {
        let s = 0;
        for (let k = 0; k < 4; k++) s += a[k * 4 + r] * b[c * 4 + k];
        o[c * 4 + r] = s;
      }
      return o;
    },
    persp(fovy, asp, n, f) {
      const t = 1 / Math.tan(fovy / 2), o = new Float32Array(16);
      o[0] = t / asp; o[5] = t; o[10] = (f + n) / (n - f); o[11] = -1; o[14] = 2 * f * n / (n - f);
      return o;
    },
    ortho(l, r, b, t, n, f) {
      const o = new Float32Array(16);
      o[0] = 2 / (r - l); o[5] = 2 / (t - b); o[10] = -2 / (f - n);
      o[12] = -(r + l) / (r - l); o[13] = -(t + b) / (t - b); o[14] = -(f + n) / (f - n); o[15] = 1;
      return o;
    },
    look(e, c, up) {
      const z = norm(sub(e, c)), x = norm(cross(up, z)), y = cross(z, x), o = new Float32Array(16);
      o[0] = x[0]; o[4] = x[1]; o[8] = x[2];
      o[1] = y[0]; o[5] = y[1]; o[9] = y[2];
      o[2] = z[0]; o[6] = z[1]; o[10] = z[2];
      o[12] = -dot(x, e); o[13] = -dot(y, e); o[14] = -dot(z, e); o[15] = 1;
      return o;
    },
    model(flipAngle, pivotZ, off) {
      // p' = R (p + off - pivot) + pivot, R a rotation about the y axis (the back view turns the case over)
      const c = Math.cos(flipAngle), s = Math.sin(flipAngle), o = new Float32Array(16);
      o[0] = c; o[2] = -s; o[5] = 1; o[8] = s; o[10] = c; o[15] = 1;
      const z0 = off[2] - pivotZ;
      o[12] = c * off[0] + s * z0; o[13] = off[1]; o[14] = -s * off[0] + c * z0 + pivotZ;
      return o;
    },
    xform(m, p) {
      const w = m[3] * p[0] + m[7] * p[1] + m[11] * p[2] + m[15];
      return [(m[0] * p[0] + m[4] * p[1] + m[8] * p[2] + m[12]) / w,
              (m[1] * p[0] + m[5] * p[1] + m[9] * p[2] + m[13]) / w,
              (m[2] * p[0] + m[6] * p[1] + m[10] * p[2] + m[14]) / w];
    },
  };
  const sub = (a, b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
  const dot = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
  const cross = (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
  const norm = a => { const l = Math.hypot(a[0], a[1], a[2]) || 1; return [a[0] / l, a[1] / l, a[2] / l]; };
  const lerp = (a, b, t) => a + (b - a) * t;
  const ease = t => t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2;
  const hex = h => { const n = parseInt(h.slice(1), 16); return [(n >> 16 & 255) / 255, (n >> 8 & 255) / 255, (n & 255) / 255].map(c => Math.pow(c, 2.2)); };

  function b64(s, Type) {
    const bin = atob(s), u8 = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) u8[i] = bin.charCodeAt(i);
    return new Type(u8.buffer);
  }

  // ---------- part catalogue (scene.js): explode layer, material, label ----------
  const SC = window.SCENE, LAYERS = SC.layers, MATS = SC.mats, THEMES = SC.themes;
  const RULES = SC.rules.map(([re, layer, mat, label]) => [new RegExp(re), { layer, mat, label }]);
  const partInfo = name => RULES.find(([re]) => re.test(name))[1];

  // ---------- shaders ----------
  const VS = `#version 300 es
  layout(location=0) in vec3 aPos; layout(location=1) in vec3 aNrm; layout(location=2) in vec2 aUv;
  uniform mat4 uModel, uVP, uLightVP;
  out vec3 vP; out vec3 vN; out vec4 vL; out vec2 vUv;
  void main(){ vec4 w = uModel*vec4(aPos,1.); vP=w.xyz; vN=mat3(uModel)*aNrm; vL=uLightVP*w; vUv=aUv;
    gl_Position=uVP*w; }`;
  const FS = `#version 300 es
  precision highp float; precision highp sampler2DShadow;
  in vec3 vP; in vec3 vN; in vec4 vL; in vec2 vUv;
  uniform vec3 uAlbedo, uCam, uKey, uFill, uRim, uAccent; uniform float uRough, uMetal, uSpec, uAlpha, uGhost, uGlow;
  uniform float uTex, uTime; uniform vec4 uClip; uniform sampler2DShadow uShadow; uniform sampler2D uImg;
  uniform float uShadowTexel;
  out vec4 o;
  const float PI=3.14159265;
  float shadow(){ vec3 p=vL.xyz/vL.w*.5+.5; if(p.z>1.) return 1.; float s=0.;
    for(int i=-2;i<=2;i++) for(int j=-2;j<=2;j++) s+=texture(uShadow, vec3(p.xy+vec2(i,j)*uShadowTexel*1.3, p.z-0.0012));
    return s/25.; }
  vec3 aces(vec3 x){ return clamp((x*(2.51*x+.03))/(x*(2.43*x+.59)+.14),0.,1.); }
  float ggx(float nh,float r){ float a=r*r, a2=a*a, d=nh*nh*(a2-1.)+1.; return a2/(PI*d*d); }
  vec3 studio(vec3 r){ // soft-box environment: bright overhead strip, warm horizon, dark floor
    float top=smoothstep(.2,.95,r.z), strip=exp(-pow((r.x+.35)*3.2,2.))*smoothstep(.3,.9,r.z);
    float side=exp(-pow((r.y-.6)*2.5,2.))*smoothstep(-.1,.5,r.z)*.6;
    return vec3(.05,.055,.065)+vec3(.55,.58,.62)*top+vec3(2.2)*strip+vec3(1.,.95,.9)*side; }
  void main(){
    if(dot(vec4(vP,1.),uClip)>0.) discard;
    vec3 V=normalize(uCam-vP), N=normalize(vN); if(!gl_FrontFacing) N=-N;
    vec3 base=uAlbedo;
    if(uTex>.5){ base=pow(texture(uImg,vUv).rgb,vec3(2.2)); o=vec4(pow(aces(base*1.15),vec3(1./2.2)),1.); return; }
    if(!gl_FrontFacing && uGhost<.5){ // section cap: flat, hatched
      float h=step(.5,fract((gl_FragCoord.x+gl_FragCoord.y)/7.));
      vec3 c=mix(base*.55+.04, base*.8+.1, h);
      o=vec4(pow(aces(c*1.3),vec3(1./2.2)),1.); return; }
    float nv=max(dot(N,V),1e-3);
    vec3 F0=mix(vec3(.04),base,uMetal), diff=base*(1.-uMetal);
    float fres=pow(1.-nv,5.);
    vec3 F=F0+(1.-F0)*fres;
    vec3 col=vec3(0.);
    float sh=shadow();
    vec3 Ls[3]=vec3[3](uKey,uFill,uRim); float Is[3]=float[3](2.9*sh,.75,1.1);
    for(int i=0;i<3;i++){ vec3 L=normalize(Ls[i]); vec3 H=normalize(L+V);
      float nl=max(dot(N,L),0.), nh=max(dot(N,H),0.);
      float k=(uRough+1.)*(uRough+1.)/8., g=nv/(nv*(1.-k)+k)*nl/(nl*(1.-k)+k+1e-4);
      vec3 spec=ggx(nh,max(uRough,.08))*g*F/(4.*nv*max(nl,1e-3)+1e-3);
      col+=(diff/PI*3.1+spec*uSpec)*nl*Is[i]; }
    float hemi=N.z*.5+.5;
    col+=diff*mix(vec3(.10,.10,.11),vec3(.36,.38,.42),hemi)*.9;
    vec3 R=reflect(-V,N);
    col+=studio(R)*F*uSpec*pow(1.-uRough,2.2)*.9;
    col+=uAccent*uGlow*(.12+.5*pow(1.-nv,2.))*(.7+.3*sin(uTime*3.));
    col=aces(col*1.05);
    vec3 srgb=pow(col,vec3(1./2.2));
    if(uGhost>0.){ float a=uAlpha*(.10+.55*pow(1.-nv,2.5)); o=vec4(mix(srgb,vec3(.75,.82,.95),.55)*a,a); return; }
    o=vec4(srgb,1.); }`;
  const VS_DEPTH = `#version 300 es
  layout(location=0) in vec3 aPos; uniform mat4 uModel, uLightVP; uniform vec4 uClip; out vec3 vP;
  void main(){ vec4 w=uModel*vec4(aPos,1.); vP=w.xyz; gl_Position=uLightVP*w; }`;
  const FS_DEPTH = `#version 300 es
  precision highp float; in vec3 vP; uniform vec4 uClip; out vec4 o;
  void main(){ if(dot(vec4(vP,1.),uClip)>0.) discard; o=vec4(1.); }`;
  const VS_LINE = `#version 300 es
  layout(location=0) in vec3 aPos; uniform mat4 uModel, uVP; out vec3 vP;
  void main(){ vec4 w=uModel*vec4(aPos,1.); vP=w.xyz; gl_Position=uVP*w; gl_Position.z-=.00004*gl_Position.w; }`;
  const FS_LINE = `#version 300 es
  precision highp float; in vec3 vP; uniform vec4 uClip, uColor; out vec4 o;
  void main(){ if(dot(vec4(vP,1.),uClip)>0.) discard; o=vec4(uColor.rgb*uColor.a,uColor.a); }`;
  const VS_GROUND = `#version 300 es
  layout(location=0) in vec3 aPos; uniform mat4 uVP, uLightVP; uniform vec3 uCenter; uniform float uZ, uSize;
  out vec3 vP; out vec4 vL;
  void main(){ vec3 p=vec3(uCenter.xy+aPos.xy*uSize, uZ); vP=p; vL=uLightVP*vec4(p,1.); gl_Position=uVP*vec4(p,1.); }`;
  const FS_GROUND = `#version 300 es
  precision highp float; precision highp sampler2DShadow;
  in vec3 vP; in vec4 vL; uniform sampler2DShadow uShadow; uniform float uShadowTexel, uSize, uZ;
  uniform vec3 uCenter; uniform vec4 uFoot; uniform float uLift; out vec4 o;
  void main(){ vec3 p=vL.xyz/vL.w*.5+.5; float s=0.;
    for(int i=-3;i<=3;i++) for(int j=-3;j<=3;j++) s+=texture(uShadow, vec3(p.xy+vec2(i,j)*uShadowTexel*2.2, p.z-0.002));
    s=1.-s/49.;
    vec2 q=abs(vP.xy-uFoot.xy)-uFoot.zw+6.; float d=length(max(q,0.))+min(max(q.x,q.y),0.)-6.;
    float ao=exp(-max(d,0.)/(5.+uLift*.6))*.45*exp(-uLift/14.);
    float r=length(vP.xy-uCenter.xy)/uSize;
    float a=clamp(s*.38+ao,0.,.75)*smoothstep(1.,.45,r);
    o=vec4(vec3(.02,.03,.05)*a,a); }`;

  function compile(gl, vs, fs) {
    const p = gl.createProgram();
    for (const [t, s] of [[gl.VERTEX_SHADER, vs], [gl.FRAGMENT_SHADER, fs]]) {
      const sh = gl.createShader(t);
      gl.shaderSource(sh, s); gl.compileShader(sh);
      if (!gl.getShaderParameter(sh, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(sh));
      gl.attachShader(p, sh);
    }
    gl.linkProgram(p);
    if (!gl.getProgramParameter(p, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(p));
    const u = {}, n = gl.getProgramParameter(p, gl.ACTIVE_UNIFORMS);
    for (let i = 0; i < n; i++) { const nm = gl.getActiveUniform(p, i).name; u[nm] = gl.getUniformLocation(p, nm); }
    return { p, u };
  }

  class Viewer {
    constructor(canvas, data, opts = {}) {
      this.canvas = canvas;
      this.labelLayer = opts.labelLayer;
      const gl = canvas.getContext('webgl2', { antialias: true, alpha: true, premultipliedAlpha: true, preserveDrawingBuffer: true });
      if (!gl) throw new Error('WebGL2 is not available');
      this.gl = gl;
      this.prog = compile(gl, VS, FS);
      this.depthProg = compile(gl, VS_DEPTH, FS_DEPTH);
      this.lineProg = compile(gl, VS_LINE, FS_LINE);
      this.groundProg = compile(gl, VS_GROUND, FS_GROUND);
      this.theme = 'midnight';
      this.parts = {};
      for (const [name, d] of Object.entries(data.parts)) this.parts[name] = this.makePart(name, d);
      this.makeScreen(data.diagram.screen_active, data.screen_png);
      this.makeGround();
      this.makeShadowMap(2048);
      // animated state
      this.cur = this.normState(opts.initial || {});
      this.from = null; this.to = this.cur; this.t0 = 0; this.dur = 1;
      this.user = { yaw: 0, pitch: 0, zoom: 1, pan: [0, 0] };
      this.t = 0;
      this.bindControls();
      this.resize();
      new ResizeObserver(() => this.resize()).observe(canvas);
      const loop = ts => { this.frame(ts); requestAnimationFrame(loop); };
      requestAnimationFrame(loop);
    }

    makePart(name, d) {
      const gl = this.gl;
      const pos = b64(d.pos, Float32Array), nrm = b64(d.nrm, Int8Array), idx = b64(d.idx, Uint32Array);
      const edges = b64(d.edges, Float32Array);
      const vao = gl.createVertexArray();
      gl.bindVertexArray(vao);
      const bp = gl.createBuffer(); gl.bindBuffer(gl.ARRAY_BUFFER, bp); gl.bufferData(gl.ARRAY_BUFFER, pos, gl.STATIC_DRAW);
      gl.enableVertexAttribArray(0); gl.vertexAttribPointer(0, 3, gl.FLOAT, false, 0, 0);
      const bn = gl.createBuffer(); gl.bindBuffer(gl.ARRAY_BUFFER, bn); gl.bufferData(gl.ARRAY_BUFFER, nrm, gl.STATIC_DRAW);
      gl.enableVertexAttribArray(1); gl.vertexAttribPointer(1, 3, gl.BYTE, true, 0, 0);
      gl.vertexAttrib2f(2, 0, 0);
      const bi = gl.createBuffer(); gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, bi); gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, idx, gl.STATIC_DRAW);
      gl.bindVertexArray(null);
      const evao = gl.createVertexArray();
      gl.bindVertexArray(evao);
      const be = gl.createBuffer(); gl.bindBuffer(gl.ARRAY_BUFFER, be); gl.bufferData(gl.ARRAY_BUFFER, edges, gl.STATIC_DRAW);
      gl.enableVertexAttribArray(0); gl.vertexAttribPointer(0, 3, gl.FLOAT, false, 0, 0);
      gl.bindVertexArray(null);
      const info = partInfo(name);
      return { name, ...info, vao, count: idx.length, evao, ecount: edges.length / 3, bounds: d.bounds };
    }

    makeScreen(aa, png) {
      const gl = this.gl, z = -2.3;
      const v = new Float32Array([aa[0], aa[1], z, aa[2], aa[1], z, aa[2], aa[3], z, aa[0], aa[3], z]);
      const uv = new Float32Array([0, 1, 1, 1, 1, 0, 0, 0]);
      const vao = gl.createVertexArray(); gl.bindVertexArray(vao);
      let b = gl.createBuffer(); gl.bindBuffer(gl.ARRAY_BUFFER, b); gl.bufferData(gl.ARRAY_BUFFER, v, gl.STATIC_DRAW);
      gl.enableVertexAttribArray(0); gl.vertexAttribPointer(0, 3, gl.FLOAT, false, 0, 0);
      gl.disableVertexAttribArray(1); gl.vertexAttrib3f(1, 0, 0, 1);
      b = gl.createBuffer(); gl.bindBuffer(gl.ARRAY_BUFFER, b); gl.bufferData(gl.ARRAY_BUFFER, uv, gl.STATIC_DRAW);
      gl.enableVertexAttribArray(2); gl.vertexAttribPointer(2, 2, gl.FLOAT, false, 0, 0);
      b = gl.createBuffer(); gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, b);
      gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, new Uint32Array([0, 1, 2, 0, 2, 3]), gl.STATIC_DRAW);
      gl.bindVertexArray(null);
      const tex = gl.createTexture();
      gl.bindTexture(gl.TEXTURE_2D, tex);
      gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, 1, 1, 0, gl.RGBA, gl.UNSIGNED_BYTE, new Uint8Array([10, 10, 30, 255]));
      if (png) {
        const img = new Image();
        img.onload = () => {
          gl.bindTexture(gl.TEXTURE_2D, tex);
          gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, img);
          gl.generateMipmap(gl.TEXTURE_2D);
          gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR);
        };
        img.src = 'data:image/png;base64,' + png;
      }
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
      this.screen = { name: 'screen', ...partInfo('screen'), vao, count: 6, tex,
                      bounds: [[aa[0], aa[1], z], [aa[2], aa[3], z]] };
    }

    makeGround() {
      const gl = this.gl;
      this.groundVao = gl.createVertexArray(); gl.bindVertexArray(this.groundVao);
      const b = gl.createBuffer(); gl.bindBuffer(gl.ARRAY_BUFFER, b);
      gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 0, 1, -1, 0, 1, 1, 0, -1, -1, 0, 1, 1, 0, -1, 1, 0]), gl.STATIC_DRAW);
      gl.enableVertexAttribArray(0); gl.vertexAttribPointer(0, 3, gl.FLOAT, false, 0, 0);
      gl.bindVertexArray(null);
    }

    makeShadowMap(n) {
      const gl = this.gl;
      this.shadowN = n;
      this.shadowTex = gl.createTexture();
      gl.bindTexture(gl.TEXTURE_2D, this.shadowTex);
      gl.texStorage2D(gl.TEXTURE_2D, 1, gl.DEPTH_COMPONENT24, n, n);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_COMPARE_MODE, gl.COMPARE_REF_TO_TEXTURE);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
      this.shadowFbo = gl.createFramebuffer();
      gl.bindFramebuffer(gl.FRAMEBUFFER, this.shadowFbo);
      gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.DEPTH_ATTACHMENT, gl.TEXTURE_2D, this.shadowTex, 0);
      gl.bindFramebuffer(gl.FRAMEBUFFER, null);
    }

    // ---------- state ----------
    normState(s) {
      const all = Object.keys(this.parts).concat('screen');
      const match = (list, n) => list.some(p => p === n || (p.endsWith('*') && n.startsWith(p.slice(0, -1))) ||
                                               p === '@' + this.info(n).layer);
      const show = s.show ? all.filter(n => match(s.show, n)) : all.filter(n => !(s.hide || []).some(p => match([p], n)));
      const focus = s.focus ? all.filter(n => match(s.focus, n)) : show;
      const vis = {}, foc = {}, glow = {};
      for (const n of all) {
        vis[n] = show.includes(n) ? 1 : 0;
        foc[n] = focus.includes(n) ? 1 : 0;
        glow[n] = s.glow && match(s.glow, n) ? 1 : 0;
      }
      const cam = Object.assign({ yaw: -28, pitch: 52, dist: 330, target: [0, 5, -15] }, s.cam || {});
      const clip = s.section ? s.section.slice() : [0, 0, 0, -1];
      return { cam, explode: s.explode || 0, flip: s.flip ? 1 : 0, vis, foc, glow, clip,
               edges: s.edges === undefined ? 1 : +s.edges, labels: s.labels || [], spread: s.spread || {},
               offset: this.expandOffsets(s.offset || {}, all, match) };
    }
    expandOffsets(off, all, match) {
      const o = {};
      for (const n of all) for (const [k, v] of Object.entries(off)) if (match([k], n)) o[n] = v;
      return o;
    }
    info(n) { return n === 'screen' ? this.screen : this.parts[n]; }

    setState(s, animate = true) {
      const to = this.normState(s);
      this.from = this.snapshot();
      this.to = to;
      this.t0 = performance.now();
      this.dur = animate ? 1100 : 1;
      this.user = { yaw: 0, pitch: 0, zoom: 1, pan: [0, 0] };
      this.labels = to.labels;
      this.renderLabels();
    }
    snapshot() { return JSON.parse(JSON.stringify(this.cur)); }

    tween(now) {
      if (!this.from) return;
      let k = Math.min(1, (now - this.t0) / this.dur);
      const e = ease(k), a = this.from, b = this.to, c = this.cur;
      let dy = b.cam.yaw - a.cam.yaw;
      c.cam = { yaw: a.cam.yaw + dy * e, pitch: lerp(a.cam.pitch, b.cam.pitch, e), dist: lerp(a.cam.dist, b.cam.dist, e),
                target: a.cam.target.map((v, i) => lerp(v, b.cam.target[i], e)) };
      c.explode = lerp(a.explode, b.explode, e);
      c.flip = lerp(a.flip, b.flip, e);
      c.edges = lerp(a.edges, b.edges, e);
      // the section plane slides in from far away instead of popping
      const off = [0, 0, 0, -1];
      const ca = a.clip[3] === -1 && !a.clip[0] && !a.clip[1] && !a.clip[2], cb = b.clip[3] === -1 && !b.clip[0] && !b.clip[1] && !b.clip[2];
      if (ca && cb) c.clip = off;
      else if (ca) c.clip = [b.clip[0], b.clip[1], b.clip[2], lerp(-200, b.clip[3], e)];
      else if (cb) c.clip = e < 1 ? [a.clip[0], a.clip[1], a.clip[2], lerp(a.clip[3], -200, e)] : off;
      else c.clip = a.clip.map((v, i) => lerp(v, b.clip[i], e));
      for (const key of ['vis', 'foc', 'glow']) for (const n in b[key]) c[key][n] = lerp(a[key][n], b[key][n], e);
      c.spread = b.spread;
      const names = new Set(Object.keys(a.offset).concat(Object.keys(b.offset)));
      c.offset = {};
      for (const n of names) { const p = a.offset[n] || [0, 0, 0], q = b.offset[n] || [0, 0, 0]; c.offset[n] = p.map((v, i) => lerp(v, q[i], e)); }
      if (k >= 1) this.from = null;
    }

    // ---------- controls ----------
    bindControls() {
      const cv = this.canvas;
      let drag = null;
      cv.addEventListener('pointerdown', e => {
        drag = { x: e.clientX, y: e.clientY, pan: e.button === 2 || e.shiftKey };
        cv.setPointerCapture(e.pointerId); cv.classList.add('dragging');
      });
      cv.addEventListener('pointermove', e => {
        if (!drag) return;
        const dx = e.clientX - drag.x, dy = e.clientY - drag.y;
        drag.x = e.clientX; drag.y = e.clientY;
        if (drag.pan) { this.user.pan[0] -= dx * 0.25 * this.user.zoom; this.user.pan[1] += dy * 0.25 * this.user.zoom; }
        else { this.user.yaw -= dx * 0.35; this.user.pitch = Math.max(-80, Math.min(80, this.user.pitch + dy * 0.3)); }
      });
      const end = () => { drag = null; cv.classList.remove('dragging'); };
      cv.addEventListener('pointerup', end); cv.addEventListener('pointercancel', end);
      cv.addEventListener('contextmenu', e => e.preventDefault());
      cv.addEventListener('wheel', e => {
        e.preventDefault();
        this.user.zoom = Math.max(0.3, Math.min(2.5, this.user.zoom * Math.exp(e.deltaY * 0.0012)));
      }, { passive: false });
      cv.addEventListener('dblclick', () => { this.user = { yaw: 0, pitch: 0, zoom: 1, pan: [0, 0] }; });
    }

    resize() {
      const r = this.canvas.getBoundingClientRect(), dpr = Math.min(window.devicePixelRatio || 1, 2);
      this.canvas.width = Math.max(1, Math.round(r.width * dpr));
      this.canvas.height = Math.max(1, Math.round(r.height * dpr));
      this.cssW = r.width; this.cssH = r.height;
    }

    // ---------- per-part transform ----------
    partOffset(n) {
      const p = this.info(n), s = this.cur.spread[n] || 0, o = this.cur.offset[n] || [0, 0, 0];
      return [o[0], o[1], o[2] + (LAYERS[p.layer] + s) * this.cur.explode];
    }
    model(n) { return M4.model(this.cur.flip * Math.PI, -17.6, this.partOffset(n)); }

    sceneBounds() {
      const lo = [1e9, 1e9, 1e9], hi = [-1e9, -1e9, -1e9];
      for (const n in this.cur.vis) {
        if (this.cur.vis[n] < 0.02) continue;
        const b = this.info(n).bounds, m = this.model(n);
        for (let i = 0; i < 8; i++) {
          const p = M4.xform(m, [b[i & 1][0], b[i >> 1 & 1][1], b[i >> 2 & 1][2]]);
          for (let k = 0; k < 3; k++) { lo[k] = Math.min(lo[k], p[k]); hi[k] = Math.max(hi[k], p[k]); }
        }
      }
      return [lo, hi];
    }

    camera() {
      const c = this.cur.cam, u = this.user;
      const yaw = (c.yaw + u.yaw) * Math.PI / 180, pitch = Math.max(-85, Math.min(88, c.pitch + u.pitch)) * Math.PI / 180;
      const dist = c.dist * u.zoom;
      const fwd = [Math.cos(pitch) * Math.sin(yaw), -Math.cos(pitch) * Math.cos(yaw), Math.sin(pitch)];
      const right = norm(cross([0, 0, 1], fwd)), up = cross(fwd, right);
      const tgt = [0, 1, 2].map(i => c.target[i] - right[i] * u.pan[0] + up[i] * u.pan[1]);
      const eye = [0, 1, 2].map(i => tgt[i] + fwd[i] * dist);
      const upv = Math.abs(fwd[2]) > 0.995 ? [0, 1, 0] : [0, 0, 1];
      const asp = this.canvas.width / this.canvas.height;
      const view = M4.look(eye, tgt, upv), proj = M4.persp(26 * Math.PI / 180, asp, 10, 3000);
      return { eye, vp: M4.mul(proj, view) };
    }

    // ---------- frame ----------
    frame(now) {
      this.t = now / 1000;
      this.tween(now);
      const gl = this.gl, s = this.cur;
      const [lo, hi] = this.sceneBounds();
      const ctr = [(lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2, (lo[2] + hi[2]) / 2];
      const rad = Math.hypot(hi[0] - lo[0], hi[1] - lo[1], hi[2] - lo[2]) / 2 + 30;
      const key = norm([-0.5, 0.35, 1.0]);
      const lightVP = M4.mul(M4.ortho(-rad, rad, -rad, rad, 1, rad * 4),
                             M4.look([0, 1, 2].map(i => ctr[i] + key[i] * rad * 2), ctr, [0, 1, 0]));
      const opaque = [], ghost = [];
      for (const n in s.vis) {
        const v = s.vis[n], f = s.foc[n];
        if (v < 0.02) continue;
        if (v > 0.98 && f > 0.5) opaque.push(n); else ghost.push(n);
      }
      // shadow pass
      gl.bindFramebuffer(gl.FRAMEBUFFER, this.shadowFbo);
      gl.viewport(0, 0, this.shadowN, this.shadowN);
      gl.clear(gl.DEPTH_BUFFER_BIT);
      gl.enable(gl.DEPTH_TEST); gl.disable(gl.BLEND); gl.disable(gl.CULL_FACE); gl.colorMask(false, false, false, false);
      gl.useProgram(this.depthProg.p);
      gl.uniformMatrix4fv(this.depthProg.u.uLightVP, false, lightVP);
      gl.uniform4fv(this.depthProg.u.uClip, s.clip);
      for (const n of opaque) {
        const p = this.info(n);
        gl.uniformMatrix4fv(this.depthProg.u.uModel, false, this.model(n));
        gl.bindVertexArray(p.vao); gl.drawElements(gl.TRIANGLES, p.count, gl.UNSIGNED_INT, 0);
      }
      gl.colorMask(true, true, true, true);
      gl.bindFramebuffer(gl.FRAMEBUFFER, null);
      gl.viewport(0, 0, this.canvas.width, this.canvas.height);
      gl.clearColor(0, 0, 0, 0);
      gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
      const cam = this.camera();
      this.vp = cam.vp;
      // ground (shadow catcher)
      const footLo = [1e9, 1e9], footHi = [-1e9, -1e9];
      let lowest = 1e9;
      for (const n of opaque) {
        const b = this.info(n).bounds, m = this.model(n);
        for (let i = 0; i < 8; i++) {
          const p = M4.xform(m, [b[i & 1][0], b[i >> 1 & 1][1], b[i >> 2 & 1][2]]);
          footLo[0] = Math.min(footLo[0], p[0]); footLo[1] = Math.min(footLo[1], p[1]);
          footHi[0] = Math.max(footHi[0], p[0]); footHi[1] = Math.max(footHi[1], p[1]);
          lowest = Math.min(lowest, p[2]);
        }
      }
      const gz = lo[2] - 0.6;
      if (opaque.length) {
        const g = this.groundProg;
        gl.useProgram(g.p);
        gl.enable(gl.BLEND); gl.blendFunc(gl.ONE, gl.ONE_MINUS_SRC_ALPHA); gl.depthMask(false);
        gl.uniformMatrix4fv(g.u.uVP, false, cam.vp); gl.uniformMatrix4fv(g.u.uLightVP, false, lightVP);
        gl.uniform3fv(g.u.uCenter, ctr); gl.uniform1f(g.u.uZ, gz); gl.uniform1f(g.u.uSize, rad * 1.6);
        gl.uniform1f(g.u.uShadowTexel, 1 / this.shadowN);
        gl.uniform4f(g.u.uFoot, (footLo[0] + footHi[0]) / 2, (footLo[1] + footHi[1]) / 2,
                     (footHi[0] - footLo[0]) / 2, (footHi[1] - footLo[1]) / 2);
        gl.uniform1f(g.u.uLift, lowest - gz);
        gl.activeTexture(gl.TEXTURE0); gl.bindTexture(gl.TEXTURE_2D, this.shadowTex); gl.uniform1i(g.u.uShadow, 0);
        gl.bindVertexArray(this.groundVao); gl.drawArrays(gl.TRIANGLES, 0, 6);
        gl.depthMask(true); gl.disable(gl.BLEND);
      }
      // opaque parts
      const P = this.prog, th = THEMES[this.theme];
      gl.useProgram(P.p);
      gl.uniformMatrix4fv(P.u.uVP, false, cam.vp); gl.uniformMatrix4fv(P.u.uLightVP, false, lightVP);
      gl.uniform3fv(P.u.uCam, cam.eye); gl.uniform4fv(P.u.uClip, s.clip);
      const flipK = s.flip > 0.5 ? -1 : 1;
      gl.uniform3fv(P.u.uKey, key); gl.uniform3fv(P.u.uFill, norm([0.8 * flipK, -0.6, 0.35]));
      gl.uniform3fv(P.u.uRim, norm([0.2, 0.9, -0.1])); gl.uniform3fv(P.u.uAccent, hex('#ffb347'));
      gl.uniform1f(P.u.uShadowTexel, 1 / this.shadowN); gl.uniform1f(P.u.uTime, this.t);
      gl.activeTexture(gl.TEXTURE0); gl.bindTexture(gl.TEXTURE_2D, this.shadowTex); gl.uniform1i(P.u.uShadow, 0);
      gl.activeTexture(gl.TEXTURE1); gl.bindTexture(gl.TEXTURE_2D, this.screen.tex); gl.uniform1i(P.u.uImg, 1);
      gl.enable(gl.POLYGON_OFFSET_FILL); gl.polygonOffset(1, 1);
      const setMat = (n, ghostA) => {
        const p = this.info(n);
        let [alb, rough, metal, spec] = MATS[p.mat] || MATS.black;
        let col = hex(alb);
        if (p.mat === 'shell') { col = hex(th.shell[0]); rough = th.shell[1]; metal = 0; spec = 0.55; }
        if (p.mat === 'button') col = hex(th.button);
        gl.uniform3fv(P.u.uAlbedo, col); gl.uniform1f(P.u.uRough, rough); gl.uniform1f(P.u.uMetal, metal);
        gl.uniform1f(P.u.uSpec, spec); gl.uniform1f(P.u.uGhost, ghostA > 0 ? 1 : 0); gl.uniform1f(P.u.uAlpha, ghostA);
        gl.uniform1f(P.u.uGlow, s.glow[n] || 0);
        gl.uniform1f(P.u.uTex, n === 'screen' && !ghostA ? 1 : 0);
        gl.uniformMatrix4fv(P.u.uModel, false, this.model(n));
      };
      for (const n of opaque) {
        const p = this.info(n);
        setMat(n, 0);
        gl.bindVertexArray(p.vao); gl.drawElements(gl.TRIANGLES, p.count, gl.UNSIGNED_INT, 0);
      }
      gl.disable(gl.POLYGON_OFFSET_FILL);
      // feature lines
      const L = this.lineProg;
      gl.useProgram(L.p);
      gl.uniformMatrix4fv(L.u.uVP, false, cam.vp); gl.uniform4fv(L.u.uClip, s.clip);
      gl.enable(gl.BLEND); gl.blendFunc(gl.ONE, gl.ONE_MINUS_SRC_ALPHA); gl.depthMask(false);
      for (const n of opaque) {
        const p = this.info(n);
        if (!p.evao || s.edges < 0.02) continue;
        const sh = hex(THEMES[this.theme].shell[0]), light = p.mat === 'shell' && sh[0] + sh[1] + sh[2] > 1.2;
        gl.uniform4f(L.u.uColor, light ? 0.25 : 0, light ? 0.27 : 0, light ? 0.3 : 0, (light ? 0.35 : 0.5) * s.edges);
        gl.uniformMatrix4fv(L.u.uModel, false, this.model(n));
        gl.bindVertexArray(p.evao); gl.drawArrays(gl.LINES, 0, p.ecount);
      }
      // ghosts: x-ray shells with faint blueprint lines
      gl.useProgram(P.p);
      for (const n of ghost) {
        const p = this.info(n);
        const a = s.vis[n] * (s.vis[n] > 0.98 ? 1 : 0.6) * (1 - 0.0 * s.foc[n]);
        setMat(n, Math.max(0.02, a));
        gl.bindVertexArray(p.vao); gl.drawElements(gl.TRIANGLES, p.count, gl.UNSIGNED_INT, 0);
      }
      gl.useProgram(L.p);
      for (const n of ghost) {
        const p = this.info(n);
        if (!p.evao) continue;
        gl.uniform4f(L.u.uColor, 0.55, 0.68, 0.9, 0.22 * s.vis[n]);
        gl.uniformMatrix4fv(L.u.uModel, false, this.model(n));
        gl.bindVertexArray(p.evao); gl.drawArrays(gl.LINES, 0, p.ecount);
      }
      gl.depthMask(true); gl.disable(gl.BLEND);
      this.placeLabels();
    }

    // ---------- labels ----------
    renderLabels() {
      if (!this.labelLayer) return;
      this.labelLayer.innerHTML = '';
      this.labelEls = (this.labels || []).map(([part, text, side, at]) => {
        const el = document.createElement('div');
        el.className = 'v-label ' + (side || 'r');
        el.innerHTML = `<span class="dot"></span><span class="line"></span><span class="txt">${text}</span>`;
        this.labelLayer.appendChild(el);
        return { el, part, side: side || 'r', at };
      });
    }
    placeLabels() {
      if (!this.labelEls || !this.vp) return;
      const fade = this.from ? Math.max(0, (performance.now() - this.t0) / this.dur - 0.7) / 0.3 : 1;
      for (const L of this.labelEls) {
        const p = this.info(L.part);
        if (!p) continue;
        const b = p.bounds;
        const local = L.at || [(b[0][0] + b[1][0]) / 2, (b[0][1] + b[1][1]) / 2, b[1][2]];
        const w = M4.xform(this.model(L.part), local);
        const c = M4.xform(this.vp, w);
        const x = (c[0] * 0.5 + 0.5) * this.cssW, y = (0.5 - c[1] * 0.5) * this.cssH;
        L.el.style.transform = `translate(${x}px, ${y}px)`;
        L.el.style.opacity = c[2] > 1 ? 0 : fade;
      }
    }

    setTheme(name) { if (THEMES[name]) this.theme = name; }
    snapshotPNG() { return this.canvas.toDataURL('image/png'); }
  }

  window.GuideViewer = Viewer;
  window.GuideThemes = THEMES;
})();
