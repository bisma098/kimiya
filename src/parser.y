%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int yylex(void);
extern int yylineno;
extern FILE *yyin;

void yyerror(const char *msg) {
    printf("line %d: %s\n", yylineno, msg);
}

/* =====================================================================
   PART 1: THE TREE (AST)
   The parser does not run anything any more. It only builds a tree of
   Nodes. After parsing is finished, PART 3 (at the bottom) runs the tree.
   ===================================================================== */

/* every kind of node in the tree */
enum NodeType {
    N_NUM,       /* a number:          16              */
    N_STR,       /* a string:          "hello"         */
    N_VAR,       /* a variable:        fuel            */
    N_BINOP,     /* two-sided operator: a + b, a > b    */
    N_NEG,       /* negative:          -a              */
    N_ASSIGN,    /* assignment:        expr -> name;   */
    N_EMIT,      /* print:             emit(a, b);     */
    N_OBSERVE    /* if/else:           observe (c) {...} otherwise {...} */
};

typedef struct Node {
    enum NodeType type;
    int line;               /* source line, for runtime error messages      */

    double num;             /* N_NUM: the number                            */
    char  *text;            /* N_STR: the string, N_VAR/N_ASSIGN: the name  */
    int    op;              /* N_BINOP: '+', '-', '*', '/', '<', '>', EQ... */

    struct Node *left;      /* N_BINOP: left side   N_NEG/N_ASSIGN: the value
                               N_EMIT: list of items  N_OBSERVE: the condition */
    struct Node *right;     /* N_BINOP: right side  N_OBSERVE: the observe block */
    struct Node *other;     /* N_OBSERVE: the otherwise block (NULL if none)  */

    struct Node *next;      /* next node in a list (statements, emit items)   */
} Node;

Node *root = NULL;          /* the whole program, set when parsing finishes */

/* create an empty node of a given type */
Node *new_node(enum NodeType type) {
    Node *n = calloc(1, sizeof(Node));   /* calloc: all fields start as 0 / NULL */
    n->type = type;
    n->line = yylineno;
    return n;
}

Node *new_num(double value) {
    Node *n = new_node(N_NUM);
    n->num = value;
    return n;
}

Node *new_str(char *text) {
    Node *n = new_node(N_STR);
    n->text = text;
    return n;
}

Node *new_var(char *name) {
    Node *n = new_node(N_VAR);
    n->text = name;
    return n;
}

Node *new_binop(int op, Node *left, Node *right) {
    Node *n = new_node(N_BINOP);
    n->op = op;
    n->left = left;
    n->right = right;
    return n;
}

Node *new_neg(Node *value) {
    Node *n = new_node(N_NEG);
    n->left = value;
    return n;
}

Node *new_assign(Node *value, char *name) {
    Node *n = new_node(N_ASSIGN);
    n->left = value;
    n->text = name;
    return n;
}

Node *new_emit(Node *items) {
    Node *n = new_node(N_EMIT);
    n->left = items;
    return n;
}

Node *new_observe(Node *cond, Node *block, Node *otherwise_block) {
    Node *n = new_node(N_OBSERVE);
    n->left  = cond;
    n->right = block;
    n->other = otherwise_block;
    return n;
}

/* add a node to the end of a list; returns the list */
Node *append(Node *list, Node *item) {
    if (list == NULL) return item;
    Node *last = list;
    while (last->next != NULL) last = last->next;
    last->next = item;
    return list;
}
%}

%union {
    double num;
    char  *str;
    struct Node *node;
}

%token <num> NUMBER
%token <str> IDENT STRING
%token EMIT ARROW OBSERVE OTHERWISE
%token EQ NE LE GE

%type <node> stmts stmt block otherwise_part emit_list emit_item expr

%nonassoc EQ NE '<' '>' LE GE
%left '+' '-'
%left '*' '/'
%right UMINUS

%%

/* =====================================================================
   PART 2: THE GRAMMAR
   Each rule only BUILDS a node. Nothing is run here.
   ===================================================================== */

program : stmts                         { root = $1; }
        ;

stmts   : /* empty */                   { $$ = NULL; }
        | stmts stmt                    { $$ = append($1, $2); }
        ;

stmt    : EMIT '(' emit_list ')' ';'    { $$ = new_emit($3); }
        | expr ARROW IDENT ';'          { $$ = new_assign($1, $3); }
        | OBSERVE '(' expr ')' block otherwise_part
                                        { $$ = new_observe($3, $5, $6); }
        ;

otherwise_part : /* empty */            { $$ = NULL; }
               | OTHERWISE block        { $$ = $2; }
               ;

block   : '{' stmts '}'                 { $$ = $2; }
        ;

emit_list : emit_item                   { $$ = $1; }
          | emit_list ',' emit_item     { $$ = append($1, $3); }
          ;

emit_item : expr                        { $$ = $1; }
          | STRING                      { $$ = new_str($1); }
          ;

expr    : NUMBER                        { $$ = new_num($1); }
        | IDENT                         { $$ = new_var($1); }
        | expr '+' expr                 { $$ = new_binop('+', $1, $3); }
        | expr '-' expr                 { $$ = new_binop('-', $1, $3); }
        | expr '*' expr                 { $$ = new_binop('*', $1, $3); }
        | expr '/' expr                 { $$ = new_binop('/', $1, $3); }
        | expr EQ expr                  { $$ = new_binop(EQ,  $1, $3); }
        | expr NE expr                  { $$ = new_binop(NE,  $1, $3); }
        | expr '<' expr                 { $$ = new_binop('<', $1, $3); }
        | expr '>' expr                 { $$ = new_binop('>', $1, $3); }
        | expr LE expr                  { $$ = new_binop(LE,  $1, $3); }
        | expr GE expr                  { $$ = new_binop(GE,  $1, $3); }
        | '-' expr %prec UMINUS         { $$ = new_neg($2); }
        | '(' expr ')'                  { $$ = $2; }
        ;

%%

/* =====================================================================
   PART 3: THE INTERPRETER
   Walks the tree and runs it.
   ===================================================================== */

/* ---------- symbol table ---------- */
#define MAX_VARS 100

char  *var_names[MAX_VARS];
double var_values[MAX_VARS];
int    var_count = 0;

void set_var(char *name, double value) {
    for (int i = 0; i < var_count; i++) {
        if (strcmp(var_names[i], name) == 0) {
            var_values[i] = value;
            return;
        }
    }
    if (var_count == MAX_VARS) {
        printf("too many variables\n");
        exit(1);
    }
    var_names[var_count]  = name;
    var_values[var_count] = value;
    var_count++;
}

double get_var(char *name, int line) {
    for (int i = 0; i < var_count; i++) {
        if (strcmp(var_names[i], name) == 0) {
            return var_values[i];
        }
    }
    printf("line %d: undefined variable '%s'\n", line, name);
    exit(1);
}

/* ---------- expressions: calculate and return a value ---------- */
double eval(Node *n) {
    switch (n->type) {
    case N_NUM:
        return n->num;

    case N_VAR:
        return get_var(n->text, n->line);

    case N_NEG:
        return -eval(n->left);

    case N_BINOP: {
        double a = eval(n->left);
        double b = eval(n->right);
        switch (n->op) {
        case '+': return a + b;
        case '-': return a - b;
        case '*': return a * b;
        case '/':
            if (b == 0) {
                printf("line %d: division by zero\n", n->line);
                exit(1);
            }
            return a / b;
        case '<': return a <  b;
        case '>': return a >  b;
        case LE:  return a <= b;
        case GE:  return a >= b;
        case EQ:  return a == b;
        case NE:  return a != b;
        }
    }

    default:
        printf("line %d: not a number\n", n->line);
        exit(1);
    }
}

/* ---------- statements: do something ---------- */
void exec_list(Node *list);

void exec(Node *n) {
    switch (n->type) {
    case N_ASSIGN:
        set_var(n->text, eval(n->left));
        break;

    case N_EMIT:
        for (Node *item = n->left; item != NULL; item = item->next) {
            if (item != n->left) printf(" ");          /* space between items */
            if (item->type == N_STR) printf("%s", item->text);
            else                     printf("%g", eval(item));
        }
        printf("\n");
        break;

    case N_OBSERVE:
        if (eval(n->left) != 0) exec_list(n->right);   /* condition true  */
        else                    exec_list(n->other);   /* condition false */
        break;

    default:
        printf("line %d: unknown statement\n", n->line);
        exit(1);
    }
}

/* run every statement in a list, in order */
void exec_list(Node *list) {
    for (Node *n = list; n != NULL; n = n->next) {
        exec(n);
    }
}

/* ---------- main ---------- */
int main(int argc, char *argv[]) {
    if (argc != 2) {
        printf("usage: ./kimiya file.kim\n");
        return 1;
    }
    yyin = fopen(argv[1], "r");
    if (yyin == NULL) {
        printf("cannot open %s\n", argv[1]);
        return 1;
    }

    if (yyparse() != 0) return 1;   /* 1. read the whole program and build the tree */
    fclose(yyin);

    exec_list(root);                /* 2. run the tree */
    return 0;
}