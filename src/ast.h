#ifndef AST_H
#define AST_H

/* Every piece of a Kimiya program becomes a Node in a tree (the AST).
   The parser builds the tree; eval.c walks it and runs it. */

typedef enum {
    N_NUM,      /* 16, 2.5           */
    N_STR,      /* "hello"           */
    N_VAR,      /* fuel              */
    N_FORMULA,  /* H2O, Ca(OH)2      */
    N_BINOP,    /* a + b, a * b ...  */
    N_ASSIGN,   /* 16 -> fuel;       */
    N_EMIT,     /* emit a, b, c;     */
    N_LIST      /* list of nodes (statements or emit arguments) */
} NodeType;

typedef struct Node {
    NodeType type;
    int line;               /* source line, for error messages */
    double num;             /* N_NUM                           */
    char *str;              /* N_STR, N_VAR, N_FORMULA, N_ASSIGN target */
    char op;                /* N_BINOP: + - * /                */
    struct Node *left;      /* N_BINOP left, N_ASSIGN value, N_EMIT args */
    struct Node *right;     /* N_BINOP right                   */
    struct Node **items;    /* N_LIST children                 */
    int count;              /* N_LIST size                     */
} Node;

Node *new_num(double v, int line);
Node *new_str(char *s, int line);
Node *new_var(char *name, int line);
Node *new_formula(char *f, int line);
Node *new_binop(char op, Node *l, Node *r, int line);
Node *new_assign(Node *value, char *name, int line);
Node *new_emit(Node *args, int line);
Node *new_list(void);
Node *list_add(Node *list, Node *item);

#endif
