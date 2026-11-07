/* =====================================================================
   runtime.c: the RUNTIME LIBRARY for programs compiled by Kimiya.

   Every Kimiya value is a "box" (a KValue) that says what is inside it.
   The LLVM IR written by the compiler only passes POINTERS to boxes
   around, and calls the small functions below to make, combine and
   print them. This file is compiled together with the .ll file.

   Every function that can fail gets the source `line`, so errors in the
   compiled program show the same line numbers as the interpreter.
   ===================================================================== */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ---------- the box ---------- */
enum KType { K_NUM, K_STR, K_FORMULA };

typedef struct {
    enum KType type;
    double     num;         /* K_NUM               */
    const char *text;       /* K_STR and K_FORMULA */
} KValue;

static const char *type_name(KValue *v) {
    switch (v->type) {
    case K_NUM:     return "a number";
    case K_STR:     return "a string";
    case K_FORMULA: return "a formula";
    }
    return "?";
}

/* ---------- making boxes ---------- */
KValue *kv_num(double num) {
    KValue *v = malloc(sizeof(KValue));
    v->type = K_NUM;
    v->num  = num;
    v->text = NULL;
    return v;
}

/* text boxes: the text itself is a global constant in the .ll file */
KValue *kv_str(const char *text) {
    KValue *v = malloc(sizeof(KValue));
    v->type = K_STR;
    v->num  = 0;
    v->text = text;
    return v;
}

KValue *kv_formula(const char *text) {
    KValue *v = malloc(sizeof(KValue));
    v->type = K_FORMULA;
    v->num  = 0;
    v->text = text;
    return v;
}

/* ---------- reading a number out of a box ---------- */
static double num_of(KValue *v, int line) {
    if (v->type != K_NUM) {
        printf("line %d: expected a number but got %s (%s)\n", line, type_name(v), v->text);
        exit(1);
    }
    return v->num;
}

/* ---------- printing (used by emit) ---------- */

/* numbers with at most 2 decimals: 16 -> "16", 2.5 -> "2.5", 43.8912 -> "43.89" */
void kv_print(KValue *v) {
    if (v->type == K_NUM) {
        char buf[64];
        sprintf(buf, "%.2f", v->num);
        char *end = buf + strlen(buf) - 1;          /* remove trailing zeros ... */
        while (*end == '0') *end-- = 0;
        if (*end == '.') *end = 0;                  /* ... and a trailing dot   */
        if (strcmp(buf, "-0") == 0) strcpy(buf, "0");
        printf("%s", buf);
    }
    else printf("%s", v->text);
}

void kv_print_space(void)   { printf(" "); }
void kv_print_newline(void) { printf("\n"); }

/* ---------- arithmetic: both boxes must hold numbers ---------- */
KValue *kv_add(KValue *a, KValue *b, int line) { return kv_num(num_of(a, line) + num_of(b, line)); }
KValue *kv_sub(KValue *a, KValue *b, int line) { return kv_num(num_of(a, line) - num_of(b, line)); }
KValue *kv_mul(KValue *a, KValue *b, int line) { return kv_num(num_of(a, line) * num_of(b, line)); }

KValue *kv_div(KValue *a, KValue *b, int line) {
    double x = num_of(a, line), y = num_of(b, line);
    if (y == 0) {
        printf("line %d: division by zero\n", line);
        exit(1);
    }
    return kv_num(x / y);
}

KValue *kv_neg(KValue *a, int line) { return kv_num(-num_of(a, line)); }
/* ---------- comparisons: the result is a number box, 1 (true) or 0 (false) ---------- */

/* == and != work on any two boxes: same type and same content */
static int same(KValue *a, KValue *b) {
    if (a->type != b->type) return 0;
    if (a->type == K_NUM)   return a->num == b->num;
    return strcmp(a->text, b->text) == 0;
}

KValue *kv_eq(KValue *a, KValue *b, int line) { (void)line; return kv_num(same(a, b)); }
KValue *kv_ne(KValue *a, KValue *b, int line) { (void)line; return kv_num(!same(a, b)); }

/* < > <= >= need two numbers */
KValue *kv_lt(KValue *a, KValue *b, int line) { return kv_num(num_of(a, line) <  num_of(b, line)); }
KValue *kv_gt(KValue *a, KValue *b, int line) { return kv_num(num_of(a, line) >  num_of(b, line)); }
KValue *kv_le(KValue *a, KValue *b, int line) { return kv_num(num_of(a, line) <= num_of(b, line)); }
KValue *kv_ge(KValue *a, KValue *b, int line) { return kv_num(num_of(a, line) >= num_of(b, line)); }

/* ---------- variables ---------- */

/* Every variable starts empty (NULL). Reading an empty variable is an error,
   exactly like "undefined variable" in the interpreter.                    */
KValue *kv_get(KValue *v, const char *name, int line) {
    if (v == NULL) {
        printf("line %d: undefined variable '%s'\n", line, name);
        exit(1);
    }
    return v;
}


/* ---------- conditions ---------- */

/* observe / loops: the condition must be a number; 0 = false, anything else = true.
   Returns 1 or 0 as a plain int, so the IR can jump on it.                       */
int kv_truth(KValue *v, int line) {
    return num_of(v, line) != 0;
}