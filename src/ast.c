#include <stdlib.h>
#include "ast.h"

static Node *make(NodeType t, int line) {
    Node *n = calloc(1, sizeof(Node));
    n->type = t;
    n->line = line;
    return n;
}

Node *new_num(double v, int line)     { Node *n = make(N_NUM, line); n->num = v; return n; }
Node *new_str(char *s, int line)      { Node *n = make(N_STR, line); n->str = s; return n; }
Node *new_var(char *name, int line)   { Node *n = make(N_VAR, line); n->str = name; return n; }
Node *new_formula(char *f, int line)  { Node *n = make(N_FORMULA, line); n->str = f; return n; }

Node *new_binop(char op, Node *l, Node *r, int line) {
    Node *n = make(N_BINOP, line);
    n->op = op; n->left = l; n->right = r;
    return n;
}

Node *new_assign(Node *value, char *name, int line) {
    Node *n = make(N_ASSIGN, line);
    n->left = value; n->str = name;
    return n;
}

Node *new_emit(Node *args, int line) {
    Node *n = make(N_EMIT, line);
    n->left = args;
    return n;
}

Node *new_list(void) { return make(N_LIST, 0); }

Node *list_add(Node *list, Node *item) {
    list->items = realloc(list->items, sizeof(Node *) * (list->count + 1));
    list->items[list->count++] = item;
    return list;
}
