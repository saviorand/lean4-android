// Minimal JNI bridge: initialise the Lean runtime and evaluate something, to prove
// Lean's GC and object model work inside an Android app process.
#include <jni.h>
#include <string.h>
#include <stdio.h>
#include <lean/lean.h>

extern void lean_initialize_runtime_module(void);
extern void lean_initialize(void);
extern lean_object * initialize_Init(uint8_t builtin, lean_object * w);
extern void lean_io_mark_end_initialization(void);

static int g_ready = 0;
static char g_status[512];

JNIEXPORT jstring JNICALL
Java_com_leanandroid_probe_MainActivity_leanProbe(JNIEnv *env, jobject thiz) {
  (void)thiz;
  if (!g_ready) {
    lean_initialize_runtime_module();
    lean_object *res = initialize_Init(1, lean_io_mk_world());
    if (lean_io_result_is_ok(res)) {
      lean_dec_ref(res);
      lean_io_mark_end_initialization();
      g_ready = 1;
    } else {
      lean_dec_ref(res);
      snprintf(g_status, sizeof g_status, "Init failed");
      return (*env)->NewStringUTF(env, g_status);
    }
  }

  // Exercise the allocator and the object model: build a Lean array, and box a
  // value large enough to occupy the top pointer byte Android would otherwise tag.
  lean_object *arr = lean_alloc_array(0, 8);
  for (size_t i = 0; i < 5; i++)
    arr = lean_array_push(arr, lean_box(i * 7));
  size_t n = lean_array_size(arr);
  size_t sum = 0;
  for (size_t i = 0; i < n; i++)
    sum += lean_unbox(lean_array_get_core(arr, i));
  lean_dec_ref(arr);

  // A string round-trip through Lean's own representation.
  lean_object *s = lean_mk_string("lean on android");
  size_t slen = lean_string_len(s);
  char buf[128];
  snprintf(buf, sizeof buf, "%s", lean_string_cstr(s));
  lean_dec_ref(s);

  snprintf(g_status, sizeof g_status,
           "Lean runtime OK\narray len=%zu sum=%zu\nstring=\"%s\" len=%zu",
           n, sum, buf, slen);
  return (*env)->NewStringUTF(env, g_status);
}
