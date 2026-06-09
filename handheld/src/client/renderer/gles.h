#ifndef NET_MINECRAFT_CLIENT_RENDERER__gles_H__
#define NET_MINECRAFT_CLIENT_RENDERER__gles_H__

#include <cstdint>

// ---- When building with Vulkan, provide type aliases and no-op macros ----

#ifdef USE_VULKAN

// Type aliases replacing GL types
using GLuint   = uint32_t;
using GLsizei  = int32_t;
using GLfloat  = float;
using GLvoid   = void;
using GLenum   = uint32_t;
using GLclampf = float;

// GL constants used by the codebase
constexpr GLenum GL_QUADS               = 0x0007;
constexpr GLenum GL_TRIANGLES           = 0x0004;
constexpr GLenum GL_ARRAY_BUFFER        = 0x8892;
constexpr GLenum GL_STATIC_DRAW         = 0x88E4;
constexpr GLenum GL_DYNAMIC_DRAW        = 0x88E8;
constexpr GLenum GL_STREAM_DRAW         = 0x88E0;
constexpr GLenum GL_COLOR_ARRAY         = 0x8076;
constexpr GLenum GL_VERTEX_ARRAY        = 0x8074;
constexpr GLenum GL_TEXTURE_COORD_ARRAY = 0x8078;
constexpr GLenum GL_NORMAL_ARRAY        = 0x8075;
constexpr GLenum GL_TEXTURE_2D          = 0x0DE1;
constexpr GLenum GL_RGBA                = 0x1908;
constexpr GLenum GL_UNSIGNED_BYTE       = 0x1401;
constexpr GLenum GL_FLOAT               = 0x1406;
constexpr GLenum GL_BYTE                = 0x1400;

// GL functions become no-ops
#define glGenBuffers(a, b)        ((void)0)
#define glBindBuffer(a, b)        ((void)0)
#define glBufferData(a, b, c, d)  ((void)0)
#define glDrawArrays(a, b, c)     ((void)0)
#define glEnable(a)               ((void)0)
#define glDisable(a)              ((void)0)

// Wrapper macros become no-ops
#define glGenBuffers2(a, b)       ((void)0)
#define glBindBuffer2(a, b)       ((void)0)
#define glBufferData2(a, b, c, d) ((void)0)
#define glDrawArrays2(a, b, c)    ((void)0)
#define glVertexPointer2(a, b, c, d)    ((void)0)
#define glColorPointer2(a, b, c, d)     ((void)0)
#define glTexCoordPointer2(a, b, c, d)  ((void)0)
#define glEnableClientState2(a)  ((void)0)
#define glDisableClientState2(a) ((void)0)
#define glEnable2(a)  ((void)0)
#define glDisable2(a) ((void)0)

// Other GL macros
#define glTranslatef(x, y, z)  ((void)0)
#define glRotatef(a, x, y, z)  ((void)0)
#define glScalef(x, y, z)      ((void)0)
#define glPushMatrix()         ((void)0)
#define glPopMatrix()          ((void)0)
#define glLoadIdentity()       ((void)0)
#define glColor4f(r, g, b, a)  ((void)0)
#define glBlendFunc(a, b)      ((void)0)
#define glShadeModel(a)        ((void)0)
#define glTexParameteri(a, b, c)  ((void)0)
#define glTexImage2D(a, b, c, d, e, f, g, h, i)  ((void)0)
#define glTexSubImage2D(a, b, c, d, e, f, g, h, i)  ((void)0)
#define glBindTexture(a, b)    ((void)0)
#define glOrthof(a, b, c, d, e, f)  ((void)0)
#define glFogf(a, b)           ((void)0)
#define glFogi(a, b)           ((void)0)
#define glFogfv(a, b)          ((void)0)
#define glEnableClientState(a) ((void)0)
#define glDisableClientState(a) ((void)0)
#define glNormalPointer(a, b, c)  ((void)0)
#define glAlphaFunc(a, b)      ((void)0)
#define glDepthFunc(a)         ((void)0)
#define glDepthMask(a)         ((void)0)
#define glScissor(a, b, c, d)  ((void)0)
#define glPolygonOffset(a, b)  ((void)0)

// Debug wrapper macros
#define glTranslatef2  glTranslatef
#define glRotatef2     glRotatef
#define glScalef2      glScalef
#define glPushMatrix2  glPushMatrix
#define glPopMatrix2   glPopMatrix
#define glLoadIdentity2 glLoadIdentity
#define glVertexPointer2(a,b,c,d) ((void)0)
#define glColorPointer2(a,b,c,d)  ((void)0)
#define glTexCoordPointer2(a,b,c,d) ((void)0)
#define glTexParameteri2 glTexParameteri
#define glTexImage2D2    glTexImage2D
#define glTexSubImage2D2 glTexSubImage2D
#define glBindTexture2   glBindTexture
#define glBlendFunc2     glBlendFunc
#define glShadeModel2    glShadeModel
#define glColor4f2       glColor4f

#define OPENGL_ES 1
#define GL_DONE

#else
// ---- Original OpenGL path (unchanged) ----

// #define USE_VBO
// #define GL_QUADS 0x0007
// #include <GLES/gl.h>
// #include <GLES/glext.h>

// // Uglyness to fix redeclaration issues
// #ifdef WIN32
// #include <WinSock2.h>
// #include <Windows.h>
// #endif
// #include <SDL3/SDL.h>

// // #define glFogx(a, b) glFogi(a, b)
// // #define glOrthof(a, b, c, d, e, f) glOrtho(a, b, c, d, e, f)

// #define GLERRDEBUG 1
// #if GLERRDEBUG
// #define GLERR(x)                                                               \
//   do {                                                                         \
//     const int errCode = glGetError();                                          \
//     if (errCode != 0)                                                          \
//       LOGE("OpenGL ERROR @%d: #%d @ (%s : %d)\n", x, errCode, __FILE__,        \
//            __LINE__);                                                          \
//   } while (0)
// #else
// #define GLERR(x) x
// #endif

// void anGenBuffers(GLsizei n, GLuint *buffer);

// #ifdef USE_VBO
// #define drawArrayVT_NoState drawArrayVT
// #define drawArrayVTC_NoState drawArrayVTC
// void drawArrayVT(int bufferId, int vertices, int vertexSize, unsigned int mode);
// #ifndef drawArrayVT_NoState
// // void drawArrayVT_NoState(int bufferId, int vertices, int vertexSize = 24);
// #endif
// void drawArrayVTC(int bufferId, int vertices, int vertexSize);
// #ifndef drawArrayVTC_NoState
// void drawArrayVTC_NoState(int bufferId, int vertices, int vertexSize4);
// #endif
// #endif

// void glInit(SDL_Window *window);
// void gluPerspective(GLfloat fovy, GLfloat aspect, GLfloat zNear, GLfloat zFar);
// int glhUnProjectf(float winx, float winy, float winz, float *modelview,
//                   float *projection, int *viewport, float *objectCoordinate);

// // Used for "debugging" (...). Obviously stupid dependency on Options (and ugly
// // gl*2 calls).
// #ifdef GLDEBUG
// #define glTranslatef2(x, y, z)                                                 \
//   do {                                                                         \
//     if (Options::debugGl)                                                      \
//       LOGI("glTrans @ %s:%d: %f,%f,%f\n", __FILE__, __LINE__, x, y, z);        \
//     glTranslatef(x, y, z);                                                     \
//     GLERR(0);                                                                  \
//   } while (0)
// #define glRotatef2(a, x, y, z)                                                 \
//   do {                                                                         \
//     if (Options::debugGl)                                                      \
//       LOGI("glRotat @ %s:%d: %f,%f,%f,%f\n", __FILE__, __LINE__, a, x, y, z);  \
//     glRotatef(a, x, y, z);                                                     \
//     GLERR(1);                                                                  \
//   } while (0)
// #define glScalef2(x, y, z)                                                     \
//   do {                                                                         \
//     if (Options::debugGl)                                                      \
//       LOGI("glScale @ %s:%d: %f,%f,%f\n", __FILE__, __LINE__, x, y, z);        \
//     glScalef(x, y, z);                                                         \
//     GLERR(2);                                                                  \
//   } while (0)
// #define glPushMatrix2()                                                        \
//   do {                                                                         \
//     if (Options::debugGl)                                                      \
//       LOGI("glPushM @ %s:%d\n", __FILE__, __LINE__);                           \
//     glPushMatrix();                                                            \
//     GLERR(3);                                                                  \
//   } while (0)
// #define glPopMatrix2()                                                         \
//   do {                                                                         \
//     if (Options::debugGl)                                                      \
//       LOGI("glPopM  @ %s:%d\n", __FILE__, __LINE__);                           \
//     glPopMatrix();                                                             \
//     GLERR(4);                                                                  \
//   } while (0)
// #define glLoadIdentity2()                                                      \
//   do {                                                                         \
//     if (Options::debugGl)                                                      \
//       LOGI("glLoadI @ %s:%d\n", __FILE__, __LINE__);                           \
//     glLoadIdentity();                                                          \
//     GLERR(5);                                                                  \
//   } while (0)

// #define glVertexPointer2(a, b, c, d)                                           \
//   do {                                                                         \
//     if (Options::debugGl)                                                      \
//       LOGI("glVertexPtr @ %s:%d : %d\n", __FILE__, __LINE__, 0);               \
//     glVertexPointer(a, b, c, d);                                               \
//     GLERR(6);                                                                  \
//   } while (0)
// #define glColorPointer2(a, b, c, d)                                            \
//   do {                                                                         \
//     if (Options::debugGl)                                                      \
//       LOGI("glColorPtr @ %s:%d : %d\n", __FILE__, __LINE__, 0);                \
//     glColorPointer(a, b, c, d);                                                \
//     GLERR(7);                                                                  \
//   } while (0)
// #define glTexCoordPointer2(a, b, c, d)                                         \
//   do {                                                                         \
//     if (Options::debugGl)                                                      \
//       LOGI("glTexPtr @ %s:%d : %d\n", __FILE__, __LINE__, 0);                  \
//     glTexCoordPointer(a, b, c, d);                                             \
//     GLERR(8);                                                                  \
//   } while (0)
// #define glEnableClientState2(s)                                                \
//   do {                                                                         \
//     if (Options::debugGl)                                                      \
//       LOGI("glEnableClient @ %s:%d : %d\n", __FILE__, __LINE__, 0);            \
//     glEnableClientState(s);                                                    \
//     GLERR(9);                                                                  \
//   } while (0)
// #define glDisableClientState2(s)                                               \
//   do {                                                                         \
//     if (Options::debugGl)                                                      \
//       LOGI("glDisableClient @ %s:%d : %d\n", __FILE__, __LINE__, 0);           \
//     glDisableClientState(s);                                                   \
//     GLERR(10);                                                                 \
//   } while (0)
// #define glDrawArrays2(m, o, v)                                                 \
//   do {                                                                         \
//     if (Options::debugGl)                                                      \
//       LOGI("glDrawA @ %s:%d : %d\n", __FILE__, __LINE__, 0);                   \
//     glDrawArrays(m, o, v);                                                     \
//     GLERR(11);                                                                 \
//   } while (0)

// #define glTexParameteri2(m, o, v)                                              \
//   do {                                                                         \
//     if (Options::debugGl)                                                      \
//       LOGI("glTexParameteri @ %s:%d : %d\n", __FILE__, __LINE__, v);           \
//     glTexParameteri(m, o, v);                                                  \
//     GLERR(12);                                                                 \
//   } while (0)
// #define glTexImage2D2(a, b, c, d, e, f, g, height, i)                          \
//   do {                                                                         \
//     if (Options::debugGl)                                                      \
//       LOGI("glTexImage2D @ %s:%d : %d\n", __FILE__, __LINE__, 0);              \
//     glTexImage2D(a, b, c, d, e, f, g, height, i);                              \
//     GLERR(13);                                                                 \
//   } while (0)
// #define glTexSubImage2D2(a, b, c, d, e, f, g, height, i)                       \
//   do {                                                                         \
//     if (Options::debugGl)                                                      \
//       LOGI("glTexSubImage2D @ %s:%d : %d\n", __FILE__, __LINE__, 0);           \
//     glTexSubImage2D(a, b, c, d, e, f, g, height, i);                           \
//     GLERR(14);                                                                 \
//   } while (0)
// #define glGenBuffers2(s, id)                                                   \
//   do {                                                                         \
//     if (Options::debugGl)                                                      \
//       LOGI("glGenBuffers @ %s:%d : %d\n", __FILE__, __LINE__, id);             \
//     anGenBuffers(s, id);                                                       \
//     GLERR(15);                                                                 \
//   } while (0)
// #define glBindBuffer2(s, id)                                                   \
//   do {                                                                         \
//     if (Options::debugGl)                                                      \
//       LOGI("glBindBuffer @ %s:%d : %d\n", __FILE__, __LINE__, id);             \
//     glBindBuffer(s, id);                                                       \
//     GLERR(16);                                                                 \
//   } while (0)
// #define glBufferData2(a, b, c, d)                                              \
//   do {                                                                         \
//     if (Options::debugGl)                                                      \
//       LOGI("glBufferData @ %s:%d : %d\n", __FILE__, __LINE__, d);              \
//     glBufferData(a, b, c, d);                                                  \
//     GLERR(17);                                                                 \
//   } while (0)
// #define glBindTexture2(m, z)                                                   \
//   do {                                                                         \
//     if (Options::debugGl)                                                      \
//       LOGI("glBindTexture @ %s:%d : %d\n", __FILE__, __LINE__, z);             \
//     glBindTexture(m, z);                                                       \
//     GLERR(18);                                                                 \
//   } while (0)

// #define glEnable2(s)                                                           \
//   do {                                                                         \
//     if (Options::debugGl)                                                      \
//       LOGI("glEnable @ %s:%d : %d\n", __FILE__, __LINE__, s);                  \
//     glEnable(s);                                                               \
//     GLERR(19);                                                                 \
//   } while (0)
// #define glDisable2(s)                                                          \
//   do {                                                                         \
//     if (Options::debugGl)                                                      \
//       LOGI("glDisable @ %s:%d : %d\n", __FILE__, __LINE__, s);                 \
//     glDisable(s);                                                              \
//     GLERR(20);                                                                 \
//   } while (0)

// #define glColor4f2(r, g, b, a)                                                 \
//   do {                                                                         \
//     if (Options::debugGl)                                                      \
//       LOGI("glColor4f2 @ %s:%d : (%f,%f,%f,%f)\n", __FILE__, __LINE__, r, g,   \
//            b, a);                                                              \
//     glColor4f(r, g, b, a);                                                     \
//     GLERR(21);                                                                 \
//   } while (0)

// // #define glBlendMode2(s) do{ if (Options::debugGl) LOGI("glEnable @ %s:%d :
// // %d\n", __FILE__, __LINE__, s); glEnable(s); GLERR(19); } while(0)
// #define glBlendFunc2(src, dst)                                                 \
//   do {                                                                         \
//     if (Options::debugGl)                                                      \
//       LOGI("glBlendFunc @ %s:%d : %d - %d\n", __FILE__, __LINE__, src, dst);   \
//     glBlendFunc(src, dst);                                                     \
//     GLERR(23);                                                                 \
//   } while (0)
// #define glShadeModel2(s)                                                       \
//   do {                                                                         \
//     if (Options::debugGl)                                                      \
//       LOGI("glShadeModel @ %s:%d : %d\n", __FILE__, __LINE__, s);              \
//     glShadeModel(s);                                                           \
//     GLERR(25);                                                                 \
//   } while (0)
// #else
// #define glTranslatef2 glTranslatef
// #define glRotatef2 glRotatef
// #define glScalef2 glScalef
// #define glPushMatrix2 glPushMatrix
// #define glPopMatrix2 glPopMatrix
// #define glLoadIdentity2 glLoadIdentity

// #define glVertexPointer2 glVertexPointer
// #define glColorPointer2 glColorPointer
// #define glTexCoordPointer2 glTexCoordPointer
// #define glEnableClientState2 glEnableClientState
// #define glDisableClientState2 glDisableClientState
// #define glDrawArrays2 glDrawArrays

// #define glTexParameteri2 glTexParameteri
// #define glTexImage2D2 glTexImage2D
// #define glTexSubImage2D2 glTexSubImage2D
// #define glGenBuffers2 anGenBuffers
// #define glBindBuffer2 glBindBuffer
// #define glBufferData2 glBufferData
// #define glBindTexture2 glBindTexture

// #define glEnable2 glEnable
// #define glDisable2 glDisable

// #define glColor4f2 glColor4f
// #define glBlendFunc2 glBlendFunc
// #define glShadeModel2 glShadeModel
// #endif

// //
// // Extensions
// //
// #ifdef WIN32
// #define glGetProcAddress(a) wglGetProcAddress(a)
// #else
// #define glGetProcAddress(a) (void *(0))
// #endif

#endif // USE_VULKAN

#endif /*NET_MINECRAFT_CLIENT_RENDERER__gles_H__ */
