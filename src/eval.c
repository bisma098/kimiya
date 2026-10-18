/* Walks the AST and executes it. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "eval.h"
#include "chem.h"

/* ---------- variables (simple table for now) ---------- */
#define MAX_VARS 256
static char *var_names[MAX_VARS];
static Value var_values[MAX_VARS];
static int var_count = 0;

static void set_var(char *name, Value v) {
    for (int i = 0; i < var_count; i++)
        if (strcmp(var_names[i], name) == 0) { var_values[i] = v; return; }
    var_names[var_count] = name;
    var_values[var_count++] = v;
}

static Value get_var(char *name, int line) {
    for (int i = 0; i < var_count; i++)
        if (strcmp(var_names[i], name) == 0) return var_values[i];
    fprintf(stderr, "line %d: undefined variable '%s'\n", line, name);
    exit(1);
}

/* ---------- expressions ---------- */
static Value eval(Node *n) {
    Value v = {0};
    switch (n->type) {
    case N_NUM:     v.type = V_NUM; v.num = n->num; break;
    case N_STR:     v.type = V_STR; v.str = n->str; break;
    case N_VAR:     v = get_var(n->str, n->line); break;
    case N_FORMULA:
        if (!chem_valid_formula(n->str)) {
            fprintf(stderr, "line %d: invalid formula '%s'\n", n->line, n->str);
            exit(1);
        }
        v.type = V_FORMULA; v.str = n->str;
        break;
    case N_BINOP: {
        Value a = eval(n->left), b = eval(n->right);
        if (a.type != V_NUM || b.type != V_NUM) {
            fprintf(stderr, "line %d: arithmetic needs numbers\n", n->line);
            exit(1);
        }
        v.type = V_NUM;
        switch (n->op) {
        case '+': v.num = a.num + b.num; break;
        case '-': v.num = a.num - b.num; break;
        case '*': v.num = a.num * b.num; break;
        case '/':
            if (b.num == 0) { fprintf(stderr, "line %d: division by zero\n", n->line); exit(1); }
            v.num = a.num / b.num; break;
        }
        break;
    }
    default:
        fprintf(stderr, "line %d: not an expression\n", n->line);
        exit(1);
    }
    return v;
}

static void print_value(Value v) {
    switch (v.type) {
    case V_NUM:     printf("%g", v.num); break;
    case V_STR:     printf("%s", v.str); break;
    case V_FORMULA: printf("%s", v.str); break;
    }
}

/* ---------- statements ---------- */
static void exec(Node *n) {
    switch (n->type) {
    case N_ASSIGN:
        set_var(n->str, eval(n->left));
        break;
    case N_EMIT:
        for (int i = 0; i < n->left->count; i++) {
            if (i > 0) printf(" ");
            print_value(eval(n->left->items[i]));
        }
        printf("\n");
        break;
    default:
        fprintf(stderr, "line %d: unknown statement\n", n->line);
        exit(1);
    }
}

void run(Node *program) {
    for (int i = 0; i < program->count; i++)
        exec(program->items[i]);
}
