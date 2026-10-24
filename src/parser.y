%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "chem.h"

int yylex(void);
extern int yylineno;
extern FILE *yyin;

void yyerror(const char *msg) {
    printf("line %d: %s\n", yylineno, msg);
}

/* =====================================================================
   PART 1: THE TREE (AST)
   The parser does not run anything. It only builds a tree of Nodes.
   After parsing is finished, PART 3 (at the bottom) runs the tree.
   ===================================================================== */

/* every kind of node in the tree */
enum NodeType {
    N_NUM,       /* a number:          16              */
    N_STR,       /* a string:          "hello"         */
    N_FORMULA,   /* a formula:         H2O, Ca(OH)2    */
    N_VAR,       /* a variable:        fuel            */
    N_BINOP,     /* two-sided operator: a + b, a > b    */
    N_NEG,       /* negative:          -a              */
    N_ASSIGN,    /* assignment:        expr -> name;   */
    N_EMIT,      /* print:             emit(a, b);     */
    N_OBSERVE,   /* if/else:           observe (c) {...} otherwise {...} */
    N_WHILE,     /* while loop:        heat while (c) {...}              */
    N_TITRATE,   /* counting loop:     titrate g from 1 to 5 {...}       */
    N_CALL       /* function call:     mass(H2O), moles(36, H2O)         */
};

typedef struct Node {
    enum NodeType type;
    int line;               /* source line, for runtime error messages      */

    double num;             /* N_NUM: the number                            */
    char  *text;            /* N_STR/N_FORMULA: the text,
                               N_VAR/N_ASSIGN/N_TITRATE: the variable name
                               N_CALL: the function name                    */
    int    op;              /* N_BINOP: '+', '-', '*', '/', '<', '>', EQ... */

    struct Node *left;      /* N_BINOP: left side   N_NEG/N_ASSIGN: the value
                               N_EMIT: list of items  N_OBSERVE/N_WHILE: condition
                               N_TITRATE: start value  N_CALL: list of arguments */
    struct Node *right;     /* N_BINOP: right side  N_OBSERVE/N_WHILE: the block
                               N_TITRATE: end value                            */
    struct Node *other;     /* N_OBSERVE: otherwise block  N_TITRATE: the block */

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

/* a formula is checked against the periodic table WHILE PARSING,
   so a wrong element stops the program before anything runs       */
Node *new_formula(char *text) {
    char symbols[MAX_ELEMENTS][3];
    int  counts[MAX_ELEMENTS];
    char bad[8];
    if (chem_count_atoms(text, symbols, counts, bad) < 0) {
        printf("line %d: unknown element '%s' in formula %s\n", yylineno, bad, text);
        exit(1);
    }
    Node *n = new_node(N_FORMULA);
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

Node *new_while(Node *cond, Node *body) {
    Node *n = new_node(N_WHILE);
    n->left  = cond;
    n->right = body;
    return n;
}

Node *new_titrate(char *var, Node *from, Node *to, Node *body) {
    Node *n = new_node(N_TITRATE);
    n->text  = var;
    n->left  = from;
    n->right = to;
    n->other = body;
    return n;
}

Node *new_call(char *name, Node *args) {
    Node *n = new_node(N_CALL);
    n->text = name;
    n->left = args;
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
%token <str> IDENT STRING FORMULA
%token EMIT ARROW OBSERVE OTHERWISE
%token HEAT WHILE TITRATE FROM TO
%token EQ NE LE GE

%type <node> stmts stmt block otherwise_part expr_list expr

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

stmt    : EMIT '(' expr_list ')' ';'    { $$ = new_emit($3); }
        | expr ARROW IDENT ';'          { $$ = new_assign($1, $3); }
        | OBSERVE '(' expr ')' block otherwise_part
                                        { $$ = new_observe($3, $5, $6); }
        | HEAT WHILE '(' expr ')' block { $$ = new_while($4, $6); }
        | TITRATE IDENT FROM expr TO expr block
                                        { $$ = new_titrate($2, $4, $6, $7); }
        ;

otherwise_part : /* empty */            { $$ = NULL; }
               | OTHERWISE block        { $$ = $2; }
               ;

block   : '{' stmts '}'                 { $$ = $2; }
        ;

/* one or more expressions separated by commas: used by emit and function calls */
expr_list : expr                        { $$ = $1; }
          | expr_list ',' expr          { $$ = append($1, $3); }
          ;

expr    : NUMBER                        { $$ = new_num($1); }
        | STRING                        { $$ = new_str($1); }
        | FORMULA                       { $$ = new_formula($1); }
        | IDENT                         { $$ = new_var($1); }
        | IDENT '(' expr_list ')'       { $$ = new_call($1, $3); }
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

/* ---------- values ----------
   A value is no longer just a double. The `type` says which field is used. */
enum ValueType { V_NUM, V_STR, V_FORMULA };

typedef struct {
    enum ValueType type;
    double num;             /* V_NUM                  */
    char  *text;            /* V_STR and V_FORMULA    */
} Value;

Value make_num(double num) {
    Value v = { V_NUM, num, NULL };
    return v;
}

Value make_text(enum ValueType type, char *text) {
    Value v = { type, 0, text };
    return v;
}

const char *type_name(Value v) {
    switch (v.type) {
    case V_NUM:     return "number";
    case V_STR:     return "string";
    case V_FORMULA: return "formula";
    }
    return "?";
}

/* get the number out of a value, or stop with an error if it is not a number */
double num_of(Value v, int line) {
    if (v.type != V_NUM) {
        printf("line %d: expected a number but got a %s (%s)\n", line, type_name(v), v.text);
        exit(1);
    }
    return v.num;
}

/* numbers are shown with at most 2 decimals: 16 -> "16", 2.5 -> "2.5", 43.8912 -> "43.89" */
void print_value(Value v) {
    if (v.type == V_NUM) {
        char buf[64];
        sprintf(buf, "%.2f", v.num);
        char *end = buf + strlen(buf) - 1;          /* remove trailing zeros ... */
        while (*end == '0') *end-- = 0;
        if (*end == '.') *end = 0;                  /* ... and a trailing dot   */
        if (strcmp(buf, "-0") == 0) strcpy(buf, "0");
        printf("%s", buf);
    }
    else printf("%s", v.text);
}

/* == and != : same type and same content */
int values_equal(Value a, Value b) {
    if (a.type != b.type) return 0;
    if (a.type == V_NUM)  return a.num == b.num;
    return strcmp(a.text, b.text) == 0;
}

/* ---------- symbol table ---------- */
#define MAX_VARS 100

char  *var_names[MAX_VARS];
Value  var_values[MAX_VARS];
int    var_count = 0;

void set_var(char *name, Value value) {
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

Value get_var(char *name, int line) {
    for (int i = 0; i < var_count; i++) {
        if (strcmp(var_names[i], name) == 0) {
            return var_values[i];
        }
    }
    printf("line %d: undefined variable '%s'\n", line, name);
    exit(1);
}

/* ---------- built-in chemistry functions ---------- */
Value eval(Node *n);

/* get a formula out of a value, or stop with an error */
char *formula_of(Value v, int line) {
    if (v.type != V_FORMULA) {
        printf("line %d: expected a formula", line);
        if (v.type == V_NUM) printf(" but got the number ");
        else                 printf(" but got the string ");
        print_value(v);
        printf("\n");
        exit(1);
    }
    return v.text;
}

/* stop with an error if a function got the wrong number of arguments */
void expect_args(Node *call, int given, int wanted, const char *usage) {
    if (given != wanted) {
        printf("line %d: %s() needs %d value(s): %s\n", call->line, call->text, wanted, usage);
        exit(1);
    }
}

#define MAX_ARGS 10

Value call_function(Node *call) {
    /* 1. calculate every argument first */
    Value args[MAX_ARGS];
    int count = 0;
    for (Node *a = call->left; a != NULL; a = a->next) {
        if (count == MAX_ARGS) {
            printf("line %d: too many values given to %s()\n", call->line, call->text);
            exit(1);
        }
        args[count++] = eval(a);
    }
    char *name = call->text;
    int line = call->line;

    /* 2. run the matching function */
    if (strcmp(name, "mass") == 0) {                       /* mass(H2O) -> 18.02 */
        expect_args(call, count, 1, "mass(formula)");
        return make_num(chem_mass(formula_of(args[0], line)));
    }
    if (strcmp(name, "moles") == 0) {                      /* moles(36, H2O) -> 2 */
        expect_args(call, count, 2, "moles(grams, formula)");
        return make_num(chem_moles(num_of(args[0], line), formula_of(args[1], line)));
    }

    printf("line %d: unknown function '%s'\n", line, name);
    exit(1);
}

/* ---------- expressions: calculate and return a value ---------- */
Value eval(Node *n) {
    switch (n->type) {
    case N_NUM:     return make_num(n->num);
    case N_STR:     return make_text(V_STR, n->text);
    case N_FORMULA: return make_text(V_FORMULA, n->text);
    case N_VAR:     return get_var(n->text, n->line);
    case N_NEG:     return make_num(-num_of(eval(n->left), n->line));
    case N_CALL:    return call_function(n);

    case N_BINOP: {
        Value a = eval(n->left);
        Value b = eval(n->right);

        /* == and != work on any type (numbers, formulas, strings) */
        if (n->op == EQ) return make_num(values_equal(a, b));
        if (n->op == NE) return make_num(!values_equal(a, b));

        /* everything else needs two numbers */
        double x = num_of(a, n->line);
        double y = num_of(b, n->line);
        switch (n->op) {
        case '+': return make_num(x + y);
        case '-': return make_num(x - y);
        case '*': return make_num(x * y);
        case '/':
            if (y == 0) {
                printf("line %d: division by zero\n", n->line);
                exit(1);
            }
            return make_num(x / y);
        case '<': return make_num(x <  y);
        case '>': return make_num(x >  y);
        case LE:  return make_num(x <= y);
        case GE:  return make_num(x >= y);
        }
    }

    default:
        printf("line %d: not an expression\n", n->line);
        exit(1);
    }
}

/* ---------- statements: do something ---------- */
void exec_list(Node *list);

/* a condition must be a number: 0 = false, anything else = true */
int is_true(Node *cond) {
    return num_of(eval(cond), cond->line) != 0;
}

void exec(Node *n) {
    switch (n->type) {
    case N_ASSIGN:
        set_var(n->text, eval(n->left));
        break;

    case N_EMIT:
        for (Node *item = n->left; item != NULL; item = item->next) {
            if (item != n->left) printf(" ");          /* space between items */
            print_value(eval(item));
        }
        printf("\n");
        break;

    case N_OBSERVE:
        if (is_true(n->left)) exec_list(n->right);     /* condition true  */
        else                  exec_list(n->other);     /* condition false */
        break;

    case N_WHILE:
        while (is_true(n->left)) {                     /* check condition, run body, repeat */
            exec_list(n->right);
        }
        break;

    case N_TITRATE: {
        double from = num_of(eval(n->left), n->line);  /* calculated once, before the loop */
        double to   = num_of(eval(n->right), n->line);
        for (double i = from; i <= to; i++) {
            set_var(n->text, make_num(i));             /* loop variable = 1, 2, 3 ...      */
            exec_list(n->other);
        }
        break;
    }

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