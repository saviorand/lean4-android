// Bridge between Compose and the Lean runtime. Everything below the JNI boundary
// runs in Lean: its allocator, its object model, its arbitrary-precision integers.
#include <jni.h>
#include <string.h>
#include <stdio.h>
#include <lean/lean.h>

extern void lean_initialize_runtime_module(void);
extern lean_object * initialize_Init(uint8_t builtin, lean_object * w);
extern void lean_io_mark_end_initialization(void);
// Nat.reprFast from the standard library; consumes its argument.
extern lean_object * l_Nat_reprFast(lean_object * n);

static int g_ready = 0;

static int ensure_init(void) {
  if (g_ready) return 1;
  lean_initialize_runtime_module();
  lean_object *res = initialize_Init(1, lean_io_mk_world());
  int ok = lean_io_result_is_ok(res);
  lean_dec_ref(res);
  if (ok) { lean_io_mark_end_initialization(); g_ready = 1; }
  return ok;
}

JNIEXPORT jboolean JNICALL
Java_com_leanandroid_compose_Lean_init(JNIEnv *e, jclass c) {
  (void)e; (void)c;
  return ensure_init() ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jstring JNICALL
Java_com_leanandroid_compose_Lean_version(JNIEnv *e, jclass c) {
  (void)c;
  if (!ensure_init()) return (*e)->NewStringUTF(e, "init failed");
  char buf[128];
  snprintf(buf, sizeof buf, "Lean %d.%d.%d on %s",
           LEAN_VERSION_MAJOR, LEAN_VERSION_MINOR, LEAN_VERSION_PATCH,
           LEAN_PLATFORM_TARGET);
  return (*e)->NewStringUTF(e, buf);
}

// Factorial through Lean's own Nat, so large values exercise its bignum path
// rather than 64-bit arithmetic that would silently overflow.
JNIEXPORT jstring JNICALL
Java_com_leanandroid_compose_Lean_factorial(JNIEnv *e, jclass c, jint n) {
  (void)c;
  if (!ensure_init()) return (*e)->NewStringUTF(e, "init failed");
  if (n < 0 || n > 2000) return (*e)->NewStringUTF(e, "out of range");

  lean_object *acc = lean_unsigned_to_nat(1u);
  for (int i = 2; i <= n; i++)
    acc = lean_nat_mul(acc, lean_unsigned_to_nat((unsigned)i));

  lean_object *s = l_Nat_reprFast(acc);   // consumes acc
  jstring out = (*e)->NewStringUTF(e, lean_string_cstr(s));
  lean_dec_ref(s);
  return out;
}

// Sums a genuine Lean linked list, so the allocator and the object layout are
// exercised rather than a plain C loop.
JNIEXPORT jlong JNICALL
Java_com_leanandroid_compose_Lean_sumTo(JNIEnv *e, jclass c, jint n) {
  (void)e; (void)c;
  if (!ensure_init()) return -1;
  lean_object *xs = lean_box(0);            // List.nil
  for (int i = n; i >= 1; i--) {
    lean_object *cell = lean_alloc_ctor(1, 2, 0);   // List.cons
    lean_ctor_set(cell, 0, lean_box((size_t)i));
    lean_ctor_set(cell, 1, xs);
    xs = cell;
  }
  long total = 0;
  lean_object *p = xs;
  while (!lean_is_scalar(p)) {
    total += (long)lean_unbox(lean_ctor_get(p, 0));
    p = lean_ctor_get(p, 1);
  }
  lean_dec_ref(xs);
  return (jlong)total;
}
