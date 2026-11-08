/* =====================================================================
   runtime.c: the RUNTIME LIBRARY for programs compiled by Kimiya.

   Every Kimiya value is a "box" (a KValue) that says what is inside it.
   The LLVM IR written by the compiler only passes POINTERS to boxes
   around, and calls the small functions below to make, combine and
   print them. This file is compiled together with the .ll file.

   Every function that can fail gets the source `line`, so errors in the
   compiled program show the same line numbers as the interpreter.
   ===================================================================== */
#include "chem.h"            
#include <stdio.h>
#include <stdlib.h>
#include <string.h>


/* ---------- the box ---------- */
enum KType { K_NUM, K_STR, K_FORMULA, K_EQUATION, K_MIXTURE, K_READINGS };

struct KList;               /* defined below: a list of boxes */

typedef struct {
    enum KType type;
    double     num;         /* K_NUM                  */
    const char *text;       /* K_STR and K_FORMULA    */
    Equation   *eq;         /* K_EQUATION             */
    struct KList *list;     /* K_MIXTURE, K_READINGS  */
} KValue;

typedef struct KList {
    int      count;
    KValue **items;         /* array of `count` pointers to boxes */
} KList;

static const char *type_name(KValue *v) {
    switch (v->type) {
    case K_NUM:     return "a number";
    case K_STR:     return "a string";
    case K_FORMULA: return "a formula";
    case K_EQUATION: return "an equation";
    case K_MIXTURE:  return "a mixture";
    case K_READINGS: return "a readings list";
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
        printf("line %d: expected a number but got %s", line, type_name(v));
        if (v->text) printf(" (%s)", v->text);
        printf("\n");
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
    else if (v->type == K_MIXTURE || v->type == K_READINGS) {   /* [H2O, CO2] */
        printf("[");
        for (int i = 0; i < v->list->count; i++) {
            if (i > 0) printf(", ");
            kv_print(v->list->items[i]);
        }
        printf("]");
    }
    else if (v->type == K_EQUATION) {               /* 2 H2 + O2 -> 2 H2O */
        char text[1000];
        chem_equation_to_text(v->eq, text);
        printf("%s", text);
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
    if (a->type == K_EQUATION) return a->eq == b->eq;        /* the same equation */
    if (a->type == K_MIXTURE || a->type == K_READINGS) return a->list == b->list;   /* the same list */
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

/* ---------- chemistry functions ---------- */

/* get the formula text out of a box, or stop with an error (like the interpreter) */
static const char *formula_of(KValue *v, int line) {
    if (v->type != K_FORMULA) {
        printf("line %d: expected a formula but got %s: ", line, type_name(v));
        kv_print(v);
        printf("\n");
        exit(1);
    }
    return v->text;
}

/* mass(H2O) -> 18.02 */
KValue *kv_mass(KValue *f, int line) {
    return kv_num(chem_mass(formula_of(f, line)));
}

/* moles(36, H2O) -> 2   (the formula is checked first, exactly like the interpreter) */
KValue *kv_moles(KValue *grams, KValue *f, int line) {
    const char *formula = formula_of(f, line);
    return kv_num(chem_moles(num_of(grams, line), formula));
}


/* ---------- equations ----------
   The compiler writes an equation as: make an empty one, then add each
   compound with its side (0 = left, 1 = right) and its coefficient.     */

KValue *kv_equation_new(void) {
    KValue *v = malloc(sizeof(KValue));
    v->type = K_EQUATION;
    v->num  = 0;
    v->text = NULL;
    v->eq   = calloc(1, sizeof(Equation));          /* calloc: no compounds yet */
    return v;
}

void kv_equation_add(KValue *v, int side, const char *formula, int coef) {
    Equation *eq = v->eq;
    if (side == 0) {
        eq->left[eq->n_left]        = (char *)formula;
        eq->left_coef[eq->n_left++] = coef;
    } else {
        eq->right[eq->n_right]        = (char *)formula;
        eq->right_coef[eq->n_right++] = coef;
    }
}

/* get the equation out of a box, or stop with an error (like the interpreter) */
static Equation *equation_of(KValue *v, int line) {
    if (v->type != K_EQUATION) {
        printf("line %d: expected an equation but got %s: ", line, type_name(v));
        kv_print(v);
        printf("\n");
        exit(1);
    }
    return v->eq;
}

/* check: report whether the equation is balanced (exactly like the interpreter) */
void kv_check(KValue *v, int line) {
    Equation *eq = equation_of(v, line);
    char text[1000], msg[1000], suggestion[1000];
    chem_equation_to_text(eq, text);
    if (chem_check(eq, msg, suggestion)) {
        printf("%s is balanced\n", text);
    } else {
        printf("%s is not balanced (%s)\n", text, msg);
        if (suggestion[0] == '(') printf("  it cannot be balanced\n");
        else                      printf("  balanced version: %s\n", suggestion);
    }
}

/* balance(eq): a NEW balanced copy; the original stays as it is */
KValue *kv_balance(KValue *v, int line) {
    Equation *copy = malloc(sizeof(Equation));
    *copy = *equation_of(v, line);
    if (!chem_balance(copy)) {
        printf("line %d: this equation cannot be balanced\n", line);
        exit(1);
    }
    KValue *b = malloc(sizeof(KValue));
    b->type = K_EQUATION;
    b->num  = 0;
    b->text = NULL;
    b->eq   = copy;
    return b;
}


/* ---------- reaction calculations ----------
   Same checks and same order as the interpreter (Part 3, call_function).   */

/* calculations give wrong answers on an unbalanced equation, so they refuse it */
static Equation *balanced_equation_of(KValue *v, int line) {
    Equation *eq = equation_of(v, line);
    char msg[1000], suggestion[1000];
    if (!chem_check(eq, msg, suggestion)) {
        char text[1000];
        chem_equation_to_text(eq, text);
        printf("line %d: the equation %s is not balanced; use balance() first\n", line, text);
        exit(1);
    }
    return eq;
}

/* stop with an error if a formula is not part of the equation */
static void must_be_in(Equation *eq, const char *formula, int line) {
    if (!chem_in_equation(eq, formula)) {
        char text[1000];
        chem_equation_to_text(eq, text);
        printf("line %d: %s is not part of the equation %s\n", line, formula, text);
        exit(1);
    }
}

/* yield(equation, reactant, grams, product): grams of product made */
KValue *kv_yield(KValue *e, KValue *from, KValue *grams, KValue *to, int line) {
    Equation *eq   = balanced_equation_of(e, line);
    const char *f  = formula_of(from, line);
    double g       = num_of(grams, line);
    const char *t  = formula_of(to, line);
    must_be_in(eq, f, line);
    must_be_in(eq, t, line);
    return kv_num(chem_yield(eq, f, g, t));
}

/* need(equation, reactant, grams, other): grams of the other reactant needed */
KValue *kv_need(KValue *e, KValue *from, KValue *grams, KValue *to, int line) {
    Equation *eq   = balanced_equation_of(e, line);
    const char *f  = formula_of(from, line);
    double g       = num_of(grams, line);
    const char *t  = formula_of(to, line);
    must_be_in(eq, f, line);
    must_be_in(eq, t, line);
    return kv_num(chem_need(eq, f, g, t));
}

/* limiting(equation, A, grams of A, B, grams of B): the formula that runs out first */
KValue *kv_limiting(KValue *e, KValue *a, KValue *ga, KValue *b, KValue *gb, int line) {
    Equation *eq   = balanced_equation_of(e, line);
    const char *fa = formula_of(a, line);
    const char *fb = formula_of(b, line);
    must_be_in(eq, fa, line);
    must_be_in(eq, fb, line);
    double xa = num_of(ga, line);
    double xb = num_of(gb, line);
    return kv_formula(chem_limiting(eq, fa, xa, fb, xb));
}

/* product(equation, A, grams of A, B, grams of B, P): grams of P made when A and B react */
KValue *kv_product(KValue *e, KValue *a, KValue *ga, KValue *b, KValue *gb, KValue *p, int line) {
    Equation *eq   = balanced_equation_of(e, line);
    const char *fa = formula_of(a, line);
    const char *fb = formula_of(b, line);
    const char *fp = formula_of(p, line);
    must_be_in(eq, fa, line);
    must_be_in(eq, fb, line);
    must_be_in(eq, fp, line);
    double xa = num_of(ga, line);
    double xb = num_of(gb, line);
    return kv_num(chem_product(eq, fa, xa, fb, xb, fp));
}


/* ---------- processes ---------- */

/* inside a process, a variable that is BOTH a local and a global: use the local
   one if it has a value yet, otherwise the global one (like the interpreter,
   which looks in the process's own variables first, then in the globals)   */
KValue *kv_get_or(KValue *local, KValue *global, const char *name, int line) {
    if (local != NULL) return local;
    return kv_get(global, name, line);
}

/* produce used in the main program, outside any process */
KValue *kv_produce_outside(int line) {
    printf("line %d: produce can only be used inside a process\n", line);
    exit(1);
}

/* count how many processes are running inside each other, so endless
   recursion stops with a clear message instead of crashing             */
static int call_depth = 0;

void kv_enter(int line) {
    if (call_depth == 500) {
        printf("line %d: too many processes inside each other (endless recursion?)\n", line);
        exit(1);
    }
    call_depth++;
}

void kv_leave(void) {
    call_depth--;
}


/* ---------- lists (mixture, readings) ---------- */

/* make an empty list box with room for `count` items; kind 0 = mixture, 1 = readings */
KValue *kv_list_new(int kind, int count) {
    KValue *v = malloc(sizeof(KValue));
    v->type = kind == 0 ? K_MIXTURE : K_READINGS;
    v->num  = 0;
    v->text = NULL;
    v->eq   = NULL;
    v->list = malloc(sizeof(KList));
    v->list->count = count;
    v->list->items = malloc(sizeof(KValue *) * (count > 0 ? count : 1));
    return v;
}

/* put item number i into the list, checking it has the right type (like the interpreter) */
void kv_list_set(KValue *v, int i, KValue *item, int line) {
    if (v->type == K_MIXTURE && item->type != K_FORMULA) {
        printf("line %d: a mixture can only hold formulas, but got %s: ", line, type_name(item));
        kv_print(item);
        printf("\n");
        exit(1);
    }
    if (v->type == K_READINGS && item->type != K_NUM) {
        printf("line %d: readings can only hold numbers, but got %s: ", line, type_name(item));
        kv_print(item);
        printf("\n");
        exit(1);
    }
    v->list->items[i] = item;
}

/* get the list out of a box, or stop with an error (like the interpreter) */
static KList *list_of(KValue *v, int line) {
    if (v->type != K_MIXTURE && v->type != K_READINGS) {
        printf("line %d: expected a mixture or readings list but got %s: ", line, type_name(v));
        kv_print(v);
        printf("\n");
        exit(1);
    }
    return v->list;
}

/* for each: how many items (as a plain int), and item number i */
int kv_list_count(KValue *v, int line) {
    return list_of(v, line)->count;
}

KValue *kv_list_get(KValue *v, int i) {
    return v->list->items[i];
}

/* count(list): how many items */
KValue *kv_count(KValue *v, int line) {
    return kv_num(list_of(v, line)->count);
}

/* average(readings): the average of the numbers */
KValue *kv_average(KValue *v, int line) {
    if (v->type != K_READINGS) {
        printf("line %d: average() needs a readings list\n", line);
        exit(1);
    }
    if (v->list->count == 0) {
        printf("line %d: average() of an empty list\n", line);
        exit(1);
    }
    double sum = 0;
    for (int i = 0; i < v->list->count; i++) sum += v->list->items[i]->num;
    return kv_num(sum / v->list->count);
}