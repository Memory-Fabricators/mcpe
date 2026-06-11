#ifndef NET_MINECRAFT_CLIENT_RENDERER__gles_H__
#define NET_MINECRAFT_CLIENT_RENDERER__gles_H__

#include "../../platform/log.h"
#include "../Options.h"

#define USE_VBO
#define GL_QUADS 0x0007
#include <GLES/gl.h>
#include <GLES/glext.h>

// Uglyness to fix redeclaration issues
#ifdef WIN32
#include <WinSock2.h>
#include <Windows.h>
#endif
#include <SDL3/SDL.h>

// #define glFogx(a, b) glFogi(a, b)
// #define glOrthof(a, b, c, d, e, f) glOrtho(a, b, c, d, e, f)

#define GLERRDEBUG 1
#if GLERRDEBUG
#define GLERR(x)                                                               \
  do {                                                                         \
    const int errCode = glGetError();                                          \
    if (errCode != 0)                                                          \
      LOGE("OpenGL ERROR @%d: #%d @ (%s : %d)\n", x, errCode, __FILE__,        \
           __LINE__);                                                          \
  } while (0)
#else
#define GLERR(x) x
#endif

void anGenBuffers(GLsizei n, GLuint *buffer);

#ifdef USE_VBO
#define drawArrayVT_NoState drawArrayVT
#define drawArrayVTC_NoState drawArrayVTC
void drawArrayVT(int bufferId, int vertices, int vertexSize, unsigned int mode);
#ifndef drawArrayVT_NoState
// void drawArrayVT_NoState(int bufferId, int vertices, int vertexSize = 24);
#endif
void drawArrayVTC(int bufferId, int vertices, int vertexSize);
#ifndef drawArrayVTC_NoState
void drawArrayVTC_NoState(int bufferId, int vertices, int vertexSize4);
#endif
#endif

void glInit(SDL_Window *window);
#ifndef USE_VK
void gluPerspective(GLfloat fovy, GLfloat aspect, GLfloat zNear, GLfloat zFar);
#endif
int glhUnProjectf(float winx, float winy, float winz, float *modelview,
                  float *projection, int *viewport, float *objectCoordinate);

// Used for "debugging" (...). Obviously stupid dependency on Options (and ugly
// gl*2 calls).
#ifdef GLDEBUG
#define glTranslatef2(x, y, z)                                                 \
  do {                                                                         \
    if (Options::debugGl)                                                      \
      LOGI("glTrans @ %s:%d: %f,%f,%f\n", __FILE__, __LINE__, x, y, z);        \
    glTranslatef(x, y, z);                                                     \
    GLERR(0);                                                                  \
  } while (0)
#define glRotatef2(a, x, y, z)                                                 \
  do {                                                                         \
    if (Options::debugGl)                                                      \
      LOGI("glRotat @ %s:%d: %f,%f,%f,%f\n", __FILE__, __LINE__, a, x, y, z);  \
    glRotatef(a, x, y, z);                                                     \
    GLERR(1);                                                                  \
  } while (0)
#define glScalef2(x, y, z)                                                     \
  do {                                                                         \
    if (Options::debugGl)                                                      \
      LOGI("glScale @ %s:%d: %f,%f,%f\n", __FILE__, __LINE__, x, y, z);        \
    glScalef(x, y, z);                                                         \
    GLERR(2);                                                                  \
  } while (0)
#define glPushMatrix2()                                                        \
  do {                                                                         \
    if (Options::debugGl)                                                      \
      LOGI("glPushM @ %s:%d\n", __FILE__, __LINE__);                           \
    glPushMatrix();                                                            \
    GLERR(3);                                                                  \
  } while (0)
#define glPopMatrix2()                                                         \
  do {                                                                         \
    if (Options::debugGl)                                                      \
      LOGI("glPopM  @ %s:%d\n", __FILE__, __LINE__);                           \
    glPopMatrix();                                                             \
    GLERR(4);                                                                  \
  } while (0)
#define glLoadIdentity2()                                                      \
  do {                                                                         \
    if (Options::debugGl)                                                      \
      LOGI("glLoadI @ %s:%d\n", __FILE__, __LINE__);                           \
    glLoadIdentity();                                                          \
    GLERR(5);                                                                  \
  } while (0)

#define glVertexPointer2(a, b, c, d)                                           \
  do {                                                                         \
    if (Options::debugGl)                                                      \
      LOGI("glVertexPtr @ %s:%d : %d\n", __FILE__, __LINE__, 0);               \
    glVertexPointer(a, b, c, d);                                               \
    GLERR(6);                                                                  \
  } while (0)
#define glColorPointer2(a, b, c, d)                                            \
  do {                                                                         \
    if (Options::debugGl)                                                      \
      LOGI("glColorPtr @ %s:%d : %d\n", __FILE__, __LINE__, 0);                \
    glColorPointer(a, b, c, d);                                                \
    GLERR(7);                                                                  \
  } while (0)
#define glTexCoordPointer2(a, b, c, d)                                         \
  do {                                                                         \
    if (Options::debugGl)                                                      \
      LOGI("glTexPtr @ %s:%d : %d\n", __FILE__, __LINE__, 0);                  \
    glTexCoordPointer(a, b, c, d);                                             \
    GLERR(8);                                                                  \
  } while (0)
#define glEnableClientState2(s)                                                \
  do {                                                                         \
    if (Options::debugGl)                                                      \
      LOGI("glEnableClient @ %s:%d : %d\n", __FILE__, __LINE__, 0);            \
    glEnableClientState(s);                                                    \
    GLERR(9);                                                                  \
  } while (0)
#define glDisableClientState2(s)                                               \
  do {                                                                         \
    if (Options::debugGl)                                                      \
      LOGI("glDisableClient @ %s:%d : %d\n", __FILE__, __LINE__, 0);           \
    glDisableClientState(s);                                                   \
    GLERR(10);                                                                 \
  } while (0)
#define glDrawArrays2(m, o, v)                                                 \
  do {                                                                         \
    if (Options::debugGl)                                                      \
      LOGI("glDrawA @ %s:%d : %d\n", __FILE__, __LINE__, 0);                   \
    glDrawArrays(m, o, v);                                                     \
    GLERR(11);                                                                 \
  } while (0)

#define glTexParameteri2(m, o, v)                                              \
  do {                                                                         \
    if (Options::debugGl)                                                      \
      LOGI("glTexParameteri @ %s:%d : %d\n", __FILE__, __LINE__, v);           \
    glTexParameteri(m, o, v);                                                  \
    GLERR(12);                                                                 \
  } while (0)
#define glTexImage2D2(a, b, c, d, e, f, g, height, i)                          \
  do {                                                                         \
    if (Options::debugGl)                                                      \
      LOGI("glTexImage2D @ %s:%d : %d\n", __FILE__, __LINE__, 0);              \
    glTexImage2D(a, b, c, d, e, f, g, height, i);                              \
    GLERR(13);                                                                 \
  } while (0)
#define glTexSubImage2D2(a, b, c, d, e, f, g, height, i)                       \
  do {                                                                         \
    if (Options::debugGl)                                                      \
      LOGI("glTexSubImage2D @ %s:%d : %d\n", __FILE__, __LINE__, 0);           \
    glTexSubImage2D(a, b, c, d, e, f, g, height, i);                           \
    GLERR(14);                                                                 \
  } while (0)
#define glGenBuffers2(s, id)                                                   \
  do {                                                                         \
    if (Options::debugGl)                                                      \
      LOGI("glGenBuffers @ %s:%d : %d\n", __FILE__, __LINE__, id);             \
    anGenBuffers(s, id);                                                       \
    GLERR(15);                                                                 \
  } while (0)
#define glBindBuffer2(s, id)                                                   \
  do {                                                                         \
    if (Options::debugGl)                                                      \
      LOGI("glBindBuffer @ %s:%d : %d\n", __FILE__, __LINE__, id);             \
    glBindBuffer(s, id);                                                       \
    GLERR(16);                                                                 \
  } while (0)
#define glBufferData2(a, b, c, d)                                              \
  do {                                                                         \
    if (Options::debugGl)                                                      \
      LOGI("glBufferData @ %s:%d : %d\n", __FILE__, __LINE__, d);              \
    glBufferData(a, b, c, d);                                                  \
    GLERR(17);                                                                 \
  } while (0)
#define glBindTexture2(m, z)                                                   \
  do {                                                                         \
    if (Options::debugGl)                                                      \
      LOGI("glBindTexture @ %s:%d : %d\n", __FILE__, __LINE__, z);             \
    glBindTexture(m, z);                                                       \
    GLERR(18);                                                                 \
  } while (0)

#define glEnable2(s)                                                           \
  do {                                                                         \
    if (Options::debugGl)                                                      \
      LOGI("glEnable @ %s:%d : %d\n", __FILE__, __LINE__, s);                  \
    glEnable(s);                                                               \
    GLERR(19);                                                                 \
  } while (0)
#define glDisable2(s)                                                          \
  do {                                                                         \
    if (Options::debugGl)                                                      \
      LOGI("glDisable @ %s:%d : %d\n", __FILE__, __LINE__, s);                 \
    glDisable(s);                                                              \
    GLERR(20);                                                                 \
  } while (0)

#define glColor4f2(r, g, b, a)                                                 \
  do {                                                                         \
    if (Options::debugGl)                                                      \
      LOGI("glColor4f2 @ %s:%d : (%f,%f,%f,%f)\n", __FILE__, __LINE__, r, g,   \
           b, a);                                                              \
    glColor4f(r, g, b, a);                                                     \
    GLERR(21);                                                                 \
  } while (0)

// #define glBlendMode2(s) do{ if (Options::debugGl) LOGI("glEnable @ %s:%d :
// %d\n", __FILE__, __LINE__, s); glEnable(s); GLERR(19); } while(0)
#define glBlendFunc2(src, dst)                                                 \
  do {                                                                         \
    if (Options::debugGl)                                                      \
      LOGI("glBlendFunc @ %s:%d : %d - %d\n", __FILE__, __LINE__, src, dst);   \
    glBlendFunc(src, dst);                                                     \
    GLERR(23);                                                                 \
  } while (0)
#define glShadeModel2(s)                                                       \
  do {                                                                         \
    if (Options::debugGl)                                                      \
      LOGI("glShadeModel @ %s:%d : %d\n", __FILE__, __LINE__, s);              \
    glShadeModel(s);                                                           \
    GLERR(25);                                                                 \
  } while (0)
#else
#define glTranslatef2 glTranslatef
#define glRotatef2 glRotatef
#define glScalef2 glScalef
#define glPushMatrix2 glPushMatrix
#define glPopMatrix2 glPopMatrix
#define glLoadIdentity2 glLoadIdentity

#define glVertexPointer2 glVertexPointer
#define glColorPointer2 glColorPointer
#define glTexCoordPointer2 glTexCoordPointer
#define glEnableClientState2 glEnableClientState
#define glDisableClientState2 glDisableClientState
#define glDrawArrays2 glDrawArrays

#define glTexParameteri2 glTexParameteri
#define glTexImage2D2 glTexImage2D
#define glTexSubImage2D2 glTexSubImage2D
#define glGenBuffers2 anGenBuffers
#define glBindBuffer2 glBindBuffer
#define glBufferData2 glBufferData
#define glBindTexture2 glBindTexture

#define glEnable2 glEnable
#define glDisable2 glDisable

#define glColor4f2 glColor4f
#define glBlendFunc2 glBlendFunc
#define glShadeModel2 glShadeModel
#endif

//
// Extensions
//
#ifdef WIN32
#define glGetProcAddress(a) wglGetProcAddress(a)
#else
#define glGetProcAddress(a) (void *(0))
#endif

#ifdef USE_VK
// ---------------------------------------------------------------------------
// Vulkan backend: redirect every GL call to its vk_* equivalent or a no-op.
// Included after the GLDEBUG macro block so we always win the redefinition.
// ---------------------------------------------------------------------------
#include "mcpe_vk.h"

// Matrix stack – direct 1:1 mapping
#undef  glMatrixMode
#undef  glLoadIdentity
#undef  glLoadIdentity2
#undef  glPushMatrix
#undef  glPushMatrix2
#undef  glPopMatrix
#undef  glPopMatrix2
#undef  glTranslatef
#undef  glTranslatef2
#undef  glRotatef
#undef  glRotatef2
#undef  glScalef
#undef  glScalef2
#define glMatrixMode(x)           ((void)0)
#define glLoadIdentity()          vk_load_identity()
#define glLoadIdentity2()         vk_load_identity()
#define glPushMatrix()            vk_push_matrix()
#define glPushMatrix2()           vk_push_matrix()
#define glPopMatrix()             vk_pop_matrix()
#define glPopMatrix2()            vk_pop_matrix()
#define glTranslatef(x,y,z)       vk_translate(x,y,z)
#define glTranslatef2(x,y,z)      vk_translate(x,y,z)
#define glRotatef(a,x,y,z)        vk_rotate(a,x,y,z)
#define glRotatef2(a,x,y,z)       vk_rotate(a,x,y,z)
#define glScalef(x,y,z)           vk_scale(x,y,z)
#define glScalef2(x,y,z)          vk_scale(x,y,z)
#define glMultMatrixf(m)          ((void)0)

// GL state – render passes handle blend/depth/cull
#undef  glEnable
#undef  glEnable2
#undef  glDisable
#undef  glDisable2
#undef  glBlendFunc
#undef  glBlendFunc2
#undef  glDepthMask
#undef  glShadeModel
#undef  glShadeModel2
#undef  glColorMask
#undef  glColor4f
#undef  glColor4f2
#define glEnable(x)               ((void)0)
#define glEnable2(x)              ((void)0)
#define glDisable(x)              ((void)0)
#define glDisable2(x)             ((void)0)
#define glBlendFunc(s,d)          ((void)0)
#define glBlendFunc2(s,d)         ((void)0)
#define glDepthMask(x)            ((void)0)
#define glShadeModel(x)           ((void)0)
#define glShadeModel2(x)          ((void)0)
#define glColorMask(r,g,b,a)      ((void)0)
#define glColor4f(r,g,b,a)        ((void)0)
#define glColor4f2(r,g,b,a)       ((void)0)
#define glDepthFunc(x)            ((void)0)
#define glDepthRangef(n,f)        ((void)0)
#define glAlphaFunc(f,v)          ((void)0)
#define glHint(t,m)               ((void)0)
#define glCullFace(x)             ((void)0)
#define glFogfv(p,v)              ((void)0)
#define glFogx(p,v)               ((void)0)
#define glFogf(p,v)               ((void)0)

// Clear – render pass handles colour; depth handled by vk_pass_gui/items
#undef  glClearColor
#undef  glClear
#define glClearColor(r,g,b,a)     vk_set_clear_color(r,g,b,a)
#define glClear(x)                ((void)0)

// Viewport – begin_frame sets this up
#define glViewport(x,y,w,h)       ((void)0)

// Texture bind (assignTexture/tick use explicit #ifdef; this covers stray sites)
#undef  glBindTexture
#undef  glBindTexture2
#define glBindTexture(t,id)       vk_texture_bind(id)
#define glBindTexture2(t,id)      vk_texture_bind(id)

// Scissor
#undef  glScissor
#define glScissor(x,y,w,h)        vk_set_scissor(x,y,w,h,1)

// GL client state / VBO – all no-ops (Tesselator redirects to vk_chunk_set)
#undef  glEnableClientState2
#undef  glDisableClientState2
#undef  glVertexPointer2
#undef  glTexCoordPointer2
#undef  glColorPointer2
#undef  glDrawArrays2
#undef  glGenBuffers2
#undef  glBindBuffer2
#undef  glBufferData2
#undef  glTexParameteri2
#undef  glTexImage2D2
#undef  glTexSubImage2D2
#define glEnableClientState2(x)                  ((void)0)
#define glDisableClientState2(x)                 ((void)0)
#define glVertexPointer2(s,t,st,p)               ((void)0)
#define glTexCoordPointer2(s,t,st,p)             ((void)0)
#define glColorPointer2(s,t,st,p)                ((void)0)
#define glDrawArrays2(m,o,v)                     ((void)0)
#define glGenBuffers2(n,ids)   anGenBuffers(n,ids)  // real IDs needed for chunk slot tracking
#define glBindBuffer2(tgt,id)  ((void)0)
#define glBufferData2(t,sz,d,u) ((void)0)
#define glTexParameteri2(t,p,v)                  ((void)0)
#define glTexImage2D2(t,l,i,w,h,b,f,ty,d)       ((void)0)
#define glTexSubImage2D2(t,l,x,y,w,h,f,ty,d)    ((void)0)

// glGetFloatv – used by FrustumCuller; redirect to vk matrix getters
#define glGetFloatv(pname, params)  \
    do { \
        if ((pname) == GL_PROJECTION_MATRIX) vk_get_projection_matrix(params); \
        else if ((pname) == GL_MODELVIEW_MATRIX) vk_get_modelview_matrix(params); \
    } while(0)

// Polygon offset — no equivalent in this renderer (depth bias can be added later)
// glOrthof – forward to vk_projection_ortho (l,r,b,t,n,f param order matches)
#define glOrthof(l,r,b,t,n,f)  vk_projection_ortho(l,r,b,t,n,f)

#define glNormal3f(x,y,z)      ((void)0)
#define glPolygonOffset(f, u)  ((void)0)
#define glLineWidth(w)         ((void)0)
#define glDeleteBuffers(n, p)  ((void)0)
#define glDeleteTextures(n, p) ((void)0)

// Error check no-op
#undef  GLERR
#define GLERR(x) ((void)0)
#define glGetError() 0

#endif /* USE_VK */

#endif /*NET_MINECRAFT_CLIENT_RENDERER__gles_H__ */
