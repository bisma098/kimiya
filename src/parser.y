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
    N_CALL,      /* function call:     mass(H2O), moles(36, H2O)         */
    N_REACTION,  /* one side ARROW other side: H2 + O2 -> H2O (used while parsing(temp)) */
    N_EQUATION,  /* equation water: H2 + O2 -> H2O;                      */
    N_CHECK,     /* check water;  or  check 2 H2 + O2 -> 2 H2O;          */
    N_PROCESS,   /* function definition: process name(a, b) {...}        */
    N_PRODUCE,   /* return a value:      produce a + b;                  */
    N_EXPR_STMT, /* an expression used as a statement: report(CO2);      */
    N_LIST,      /* a list:              mixture lab = [H2O, CO2];       */
    N_EACH       /* list loop:           each c in lab {...}             */
};

typedef struct Node {
    enum NodeType type;
    int line;               /* source line, for runtime error messages      */

    double num;             /* N_NUM: the number
                               N_FORMULA inside a reaction: its coefficient  */

    char  *text;            /* N_STR/N_FORMULA: the text,
                               N_VAR/N_ASSIGN/N_TITRATE/N_EACH: the variable name
                               N_CALL/N_PROCESS: the function name          */

    int    op;              /* N_BINOP: '+', '-', '*', '/', '<', '>', EQ...
                               N_LIST: MIXTURE or READINGS                  */

    struct Node *left;      /* N_BINOP: left side  
                                N_NEG/N_ASSIGN: the value
                               N_EMIT: list of items  
                               N_OBSERVE/N_WHILE: condition
                               N_TITRATE: start value  
                               N_CALL: list of arguments
                               N_PROCESS: list of parameter names
                               N_PRODUCE/N_EXPR_STMT: the value
                               N_LIST: list of items   N_EACH: the list   */

    struct Node *right;     /* N_BINOP: right side  
                                N_OBSERVE/N_WHILE: the block
                               N_TITRATE: end value
                               N_PROCESS: the body    N_EACH: the block  */

    struct Node *other;     /* N_OBSERVE: otherwise block  
                                N_TITRATE: the block */

    struct Node *next;      /* next node in a list (statements, emit items)   */

    Equation *eq;           /* N_EQUATION/N_CHECK: the equation             */
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

/* ---------- equations ----------
   A reaction like  2 H2 + O2 -> 2 H2O  is parsed as a N_REACTION node:
   left = list of formula nodes on the left, right = list on the right.
   Each formula node keeps its coefficient in `num` (1 if none was written)
   and `op` = 1 if the user wrote a coefficient.                           */

Node *new_term(double coef, char *formula, int written) {
    if (coef < 1 || coef != (int)coef) {
        printf("line %d: coefficient of %s must be a whole number of 1 or more\n", yylineno, formula);
        exit(1);
    }
    Node *n = new_formula(formula);     /* also checks the elements */
    n->num = coef;
    n->op  = written;
    return n;
}

Node *new_reaction(Node *left, Node *right) {
    Node *n = new_node(N_REACTION);
    n->left  = left;
    n->right = right;
    return n;
}

/* copy a parsed reaction into the Equation struct that chem.c uses */
Equation *to_equation(Node *reaction) {
    Equation *eq = calloc(1, sizeof(Equation));
    for (Node *t = reaction->left; t != NULL; t = t->next) {
        if (eq->n_left == MAX_COMPOUNDS) { printf("line %d: too many compounds\n", yylineno); exit(1); }
        eq->left[eq->n_left]      = t->text;
        eq->left_coef[eq->n_left] = (int)t->num;
        eq->n_left++;
    }
    for (Node *t = reaction->right; t != NULL; t = t->next) {
        if (eq->n_right == MAX_COMPOUNDS) { printf("line %d: too many compounds\n", yylineno); exit(1); }
        eq->right[eq->n_right]      = t->text;
        eq->right_coef[eq->n_right] = (int)t->num;
        eq->n_right++;
    }
    return eq;
}

/* equation name: reaction;   ->  stored EXACTLY as written (balanced or not).
   Use `check` to test it and balance() to get the balanced version.        */
Node *new_equation(char *name, Node *reaction) {
    Node *n = new_node(N_EQUATION);
    n->text = name;
    n->eq   = to_equation(reaction);
    return n;
}

/* check name;          ->  left = the variable, checked when the program runs
   check reaction;      ->  eq   = the written equation, checked when the program runs */
Node *new_check_var(Node *var) {
    Node *n = new_node(N_CHECK);
    n->left = var;
    return n;
}

Node *new_check_reaction(Node *reaction) {
    Node *n = new_node(N_CHECK);
    n->eq = to_equation(reaction);
    return n;
}

/* ---------- processes (user functions) ----------
   Every `process` is stored in this table WHILE PARSING, so a process can be
   called anywhere in the program (even before it is written) and can call itself. */
#define MAX_PROCESSES 100
Node *processes[MAX_PROCESSES];
int   process_count = 0;

Node *find_process(char *name) {
    for (int i = 0; i < process_count; i++)
        if (strcmp(processes[i]->text, name) == 0) return processes[i];
    return NULL;
}

/* process name(params) { body }:  text = name, left = parameter names, right = body */
Node *new_process(char *name, Node *params, Node *body) {
    const char *builtins[] = { "mass", "moles", "balance", "yield", "need", "limiting",
                               "product", "count", "average", NULL };
    for (int i = 0; builtins[i]; i++)
        if (strcmp(name, builtins[i]) == 0) {
            printf("line %d: '%s' is a built-in function, choose another name\n", yylineno, name);
            exit(1);
        }
    if (find_process(name)) {
        printf("line %d: process '%s' is already defined\n", yylineno, name);
        exit(1);
    }
    if (process_count == MAX_PROCESSES) {
        printf("line %d: too many processes\n", yylineno);
        exit(1);
    }
    Node *n = new_node(N_PROCESS);
    n->text  = name;
    n->left  = params;
    n->right = body;
    processes[process_count++] = n;
    return NULL;                         /* nothing to run where the process is written */
}

Node *new_produce(Node *value) {
    Node *n = new_node(N_PRODUCE);
    n->left = value;
    return n;
}

Node *new_expr_stmt(Node *value) {
    Node *n = new_node(N_EXPR_STMT);
    n->left = value;
    return n;
}

/* ---------- lists ----------
   mixture lab = [H2O, CO2];   ->  an assignment whose value is a N_LIST node
   kind = MIXTURE (only formulas allowed) or READINGS (only numbers allowed) */
Node *new_list(int kind, Node *items) {
    Node *n = new_node(N_LIST);
    n->op   = kind;
    n->left = items;
    return n;
}

Node *new_each(char *var, Node *list, Node *body) {
    Node *n = new_node(N_EACH);
    n->text  = var;
    n->left  = list;
    n->right = body;
    return n;
}

/* add a node to the end of a list; returns the list */
Node *append(Node *list, Node *item) {
    if (item == NULL) return list;      /* e.g. a process definition adds nothing to run */
    if (list == NULL) return item;
    Node *last = list;
    while (last->next != NULL) last = last->next;
    last->next = item;
    return list;
}
%}

%define parse.error verbose

%union {
    double num;
    char  *str;
    struct Node *node;
}

%token <num> NUMBER
%token <str> IDENT STRING FORMULA
%token EMIT ARROW OBSERVE OTHERWISE
%token HEAT WHILE TITRATE FROM TO
%token EQUATION CHECK
%token PROCESS PRODUCE
%token MIXTURE READINGS EACH IN
%token EQ NE LE GE

%type <node> stmts stmt block otherwise_part expr_list expr
%type <node> reaction side term
%type <node> params param_list list_items

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
        | EQUATION IDENT ':' reaction ';'
                                        { $$ = new_equation($2, $4); }
        | CHECK IDENT ';'               { $$ = new_check_var(new_var($2)); }
        | CHECK reaction ';'            { $$ = new_check_reaction($2); }
        | PROCESS IDENT '(' params ')' block
                                        { $$ = new_process($2, $4, $6); }
        | PRODUCE expr ';'              { $$ = new_produce($2); }
        | expr ';'                      { $$ = new_expr_stmt($1); }
        | MIXTURE IDENT '=' '[' list_items ']' ';'
                                        { $$ = new_assign(new_list(MIXTURE, $5), $2); }
        | READINGS IDENT '=' '[' list_items ']' ';'
                                        { $$ = new_assign(new_list(READINGS, $5), $2); }
        | EACH IDENT IN expr block      { $$ = new_each($2, $4, $5); }
        ;

/* parameter names of a process: none, or names separated by commas */
params  : /* empty */                   { $$ = NULL; }
        | param_list                    { $$ = $1; }
        ;

param_list : IDENT                      { $$ = new_var($1); }
           | param_list ',' IDENT       { $$ = append($1, new_var($3)); }
           ;

/* items of a list: none, or expressions separated by commas */
list_items : /* empty */                { $$ = NULL; }
           | expr_list                  { $$ = $1; }
           ;

/* a chemical reaction:  2 H2 + O2 -> 2 H2O */
reaction : side ARROW side              { $$ = new_reaction($1, $3); }
         ;

side    : term                          { $$ = $1; }
        | side '+' term                 { $$ = append($1, $3); }
        ;

term    : FORMULA                       { $$ = new_term(1,  $1, 0); }
        | NUMBER FORMULA                { $$ = new_term($1, $2, 1); }
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
        | IDENT '(' ')'                 { $$ = new_call($1, NULL); }
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
enum ValueType { V_NUM, V_STR, V_FORMULA, V_EQUATION, V_MIXTURE, V_READINGS };

struct List;                /* defined below: a list of values */

typedef struct {
    enum ValueType type;
    double num;             /* V_NUM                  */
    char  *text;            /* V_STR and V_FORMULA    */
    Equation *eq;           /* V_EQUATION             */
    struct List *list;      /* V_MIXTURE, V_READINGS  */
} Value;

typedef struct List {
    int    count;
    Value *items;           /* array of `count` values */
} List;

Value make_num(double num) {
    Value v = { V_NUM, num, NULL, NULL, NULL };
    return v;
}

Value make_text(enum ValueType type, char *text) {
    Value v = { type, 0, text, NULL, NULL };
    return v;
}

Value make_equation(Equation *eq) {
    Value v = { V_EQUATION, 0, NULL, eq, NULL };
    return v;
}

Value make_list(enum ValueType type, List *list) {
    Value v = { type, 0, NULL, NULL, list };
    return v;
}

const char *type_name(Value v) {
    switch (v.type) {
    case V_NUM:     return "a number";
    case V_STR:     return "a string";
    case V_FORMULA: return "a formula";
    case V_EQUATION: return "an equation";
    case V_MIXTURE:  return "a mixture";
    case V_READINGS: return "a readings list";
    }
    return "?";
}

/* get the number out of a value, or stop with an error if it is not a number */
double num_of(Value v, int line) {
    if (v.type != V_NUM) {
        printf("line %d: expected a number but got %s", line, type_name(v));
        if (v.text) printf(" (%s)", v.text);
        printf("\n");
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
    else if (v.type == V_EQUATION) {
        char text[1000];
        chem_equation_to_text(v.eq, text);
        printf("%s", text);
    }
    else if (v.type == V_MIXTURE || v.type == V_READINGS) {   /* [H2O, CO2] */
        printf("[");
        for (int i = 0; i < v.list->count; i++) {
            if (i > 0) printf(", ");
            print_value(v.list->items[i]);
        }
        printf("]");
    }
    else printf("%s", v.text);
}

/* == and != : same type and same content */
int values_equal(Value a, Value b) {
    if (a.type != b.type) return 0;
    if (a.type == V_NUM)  return a.num == b.num;
    if (a.type == V_EQUATION) return a.eq == b.eq;
    if (a.type == V_MIXTURE || a.type == V_READINGS) return a.list == b.list;
    return strcmp(a.text, b.text) == 0;
}

/* ---------- symbol table ----------
   All variables live in one array used like a stack:

      [ global variables | variables of call 1 | variables of call 2 ... ]
        0 .. global_end     frame_start .. var_count  (the running process)

   Outside any process frame_start = 0, so everything is global.
   When a process is called, its variables are added on top (a new "frame")
   and removed again when it finishes.                                      */
#define MAX_VARS 1000

char  *var_names[MAX_VARS];
Value  var_values[MAX_VARS];
int    var_count   = 0;
int    frame_start = 0;     /* first variable of the running process (0 = not in a process) */
int    global_end  = 0;     /* global variables are 0 .. global_end-1 while a process runs  */
int    call_depth  = 0;     /* how many processes are running inside each other            */

/* search one part of the array; returns the index or -1 */
int find_var(char *name, int from, int to) {
    for (int i = from; i < to; i++)
        if (strcmp(var_names[i], name) == 0) return i;
    return -1;
}

/* assignment always goes into the current frame (inside a process: a local variable) */
void set_var(char *name, Value value) {
    int i = find_var(name, frame_start, var_count);
    if (i >= 0) {
        var_values[i] = value;
        return;
    }
    if (var_count == MAX_VARS) {
        printf("too many variables\n");
        exit(1);
    }
    var_names[var_count]  = name;
    var_values[var_count] = value;
    var_count++;
}

/* look in the current frame first, then in the global variables */
Value get_var(char *name, int line) {
    int i = find_var(name, frame_start, var_count);
    if (i < 0 && call_depth > 0) i = find_var(name, 0, global_end);
    if (i < 0) {
        printf("line %d: undefined variable '%s'\n", line, name);
        exit(1);
    }
    return var_values[i];
}

/* ---------- built-in functions ---------- */
Value eval(Node *n);
void exec_list(Node *list);
Value call_process(Node *proc, Node *call, Value args[], int count);

/* produce: set when a `produce` runs, so the process stops and returns this value */
int   producing = 0;
Value produced;

/* get a formula out of a value, or stop with an error */
char *formula_of(Value v, int line) {
    if (v.type != V_FORMULA) {
        printf("line %d: expected a formula", line);
        printf(" but got %s: ", type_name(v));
        print_value(v);
        printf("\n");
        exit(1);
    }
    return v.text;
}

/* get an equation out of a value, or stop with an error */
Equation *equation_of(Value v, int line) {
    if (v.type != V_EQUATION) {
        printf("line %d: expected an equation but got %s: ", line, type_name(v));
        print_value(v);
        printf("\n");
        exit(1);
    }
    return v.eq;
}

/* 1 if the equation's coefficients are balanced, 0 if not */
int is_balanced(Equation *eq) {
    char msg[1000], suggestion[1000];
    return chem_check(eq, msg, suggestion);
}

/* For calculations (yield, need, limiting, product): they give wrong answers on an
   unbalanced equation, so they must get their equation through this function.   */
Equation *balanced_equation_of(Value v, int line) {
    Equation *eq = equation_of(v, line);
    if (!is_balanced(eq)) {
        char text[1000];
        chem_equation_to_text(eq, text);
        printf("line %d: the equation %s is not balanced; use balance() first\n", line, text);
        exit(1);
    }
    return eq;
}

/* stop with an error if a formula is not part of the equation */
void must_be_in(Equation *eq, char *formula, int line) {
    if (!chem_in_equation(eq, formula)) {
        char text[1000];
        chem_equation_to_text(eq, text);
        printf("line %d: %s is not part of the equation %s\n", line, formula, text);
        exit(1);
    }
}

/* get a list out of a value, or stop with an error */
List *list_of(Value v, int line) {
    if (v.type != V_MIXTURE && v.type != V_READINGS) {
        printf("line %d: expected a mixture or readings list but got %s: ", line, type_name(v));
        print_value(v);
        printf("\n");
        exit(1);
    }
    return v.list;
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

    /* 2a. a process written by the user? */
    Node *proc = find_process(name);
    if (proc != NULL) return call_process(proc, call, args, count);

    /* 2b. a built-in function? */
    if (strcmp(name, "mass") == 0) {                       /* mass(H2O) -> 18.02 */
        expect_args(call, count, 1, "mass(formula)");
        return make_num(chem_mass(formula_of(args[0], line)));
    }
    if (strcmp(name, "moles") == 0) {                      /* moles(36, H2O) -> 2 */
        expect_args(call, count, 2, "moles(grams, formula)");
        return make_num(chem_moles(num_of(args[0], line), formula_of(args[1], line)));
    }

        /* balance(equation): a NEW equation with the correct coefficients.
       The original is not changed:  balance(hw) -> hw;  replaces it.  */
    if (strcmp(name, "balance") == 0) {
        expect_args(call, count, 1, "balance(equation)");
        Equation *copy = malloc(sizeof(Equation));
        *copy = *equation_of(args[0], line);          /* copy, so the original stays as it is */
        if (!chem_balance(copy)) {
            printf("line %d: this equation cannot be balanced\n", line);
            exit(1);
        }
        return make_equation(copy);
    }

    /* yield(equation, reactant, grams, product): grams of product made
       need (equation, reactant, grams, other):   grams of the other reactant needed */
    if (strcmp(name, "yield") == 0 || strcmp(name, "need") == 0) {
        expect_args(call, count, 4, strcmp(name, "yield") == 0
                    ? "yield(equation, reactant, grams, product)"
                    : "need(equation, reactant, grams, other)");
        Equation *eq = balanced_equation_of(args[0], line);
        char *from   = formula_of(args[1], line);
        double grams = num_of(args[2], line);
        char *to     = formula_of(args[3], line);
        must_be_in(eq, from, line);
        must_be_in(eq, to, line);
        if (strcmp(name, "yield") == 0) return make_num(chem_yield(eq, from, grams, to));
        else                            return make_num(chem_need(eq, from, grams, to));
    }

    /* limiting(equation, A, grams of A, B, grams of B): the formula that runs out first */
    if (strcmp(name, "limiting") == 0) {
        expect_args(call, count, 5, "limiting(equation, A, grams, B, grams)");
        Equation *eq = balanced_equation_of(args[0], line);
        char *a = formula_of(args[1], line);
        char *b = formula_of(args[3], line);
        must_be_in(eq, a, line);
        must_be_in(eq, b, line);
        const char *lim = chem_limiting(eq, a, num_of(args[2], line), b, num_of(args[4], line));
        return make_text(V_FORMULA, (char *)lim);
    }

    /* product(equation, A, grams of A, B, grams of B, P): grams of P made when A and B react */
    if (strcmp(name, "product") == 0) {
        expect_args(call, count, 6, "product(equation, A, grams, B, grams, product)");
        Equation *eq = balanced_equation_of(args[0], line);
        char *a = formula_of(args[1], line);
        char *b = formula_of(args[3], line);
        char *p = formula_of(args[5], line);
        must_be_in(eq, a, line);
        must_be_in(eq, b, line);
        must_be_in(eq, p, line);
        return make_num(chem_product(eq, a, num_of(args[2], line), b, num_of(args[4], line), p));
    }

    /* count(list): how many items */
    if (strcmp(name, "count") == 0) {
        expect_args(call, count, 1, "count(list)");
        return make_num(list_of(args[0], line)->count);
    }

    /* average(readings): the average of the numbers */
    if (strcmp(name, "average") == 0) {
        expect_args(call, count, 1, "average(readings)");
        if (args[0].type != V_READINGS) {
            printf("line %d: average() needs a readings list\n", line);
            exit(1);
        }
        List *list = args[0].list;
        if (list->count == 0) {
            printf("line %d: average() of an empty list\n", line);
            exit(1);
        }
        double sum = 0;
        for (int i = 0; i < list->count; i++) sum += list->items[i].num;
        return make_num(sum / list->count);
    }

    printf("line %d: unknown function '%s'\n", line, name);
    exit(1);
}

/* run a user process: new frame, parameters = argument values, run the body */
#define MAX_CALL_DEPTH 500

Value call_process(Node *proc, Node *call, Value args[], int count) {
    int wanted = 0;
    for (Node *p = proc->left; p != NULL; p = p->next) wanted++;
    if (count != wanted) {
        printf("line %d: process %s() needs %d value(s) but got %d\n", call->line, proc->text, wanted, count);
        exit(1);
    }
    if (call_depth == MAX_CALL_DEPTH) {
        printf("line %d: too many processes inside each other (endless recursion?)\n", call->line);
        exit(1);
    }

    /* 1. start a new frame on top of the stack */
    int old_frame_start = frame_start;
    int old_var_count   = var_count;
    if (call_depth == 0) global_end = var_count;     /* everything so far is global */
    frame_start = var_count;
    call_depth++;

    /* 2. parameters become local variables */
    int i = 0;
    for (Node *p = proc->left; p != NULL; p = p->next) set_var(p->text, args[i++]);

    /* 3. run the body until it ends or a produce runs */
    producing = 0;
    exec_list(proc->right);
    Value result = producing ? produced : make_num(0);   /* no produce -> 0 */
    producing = 0;

    /* 4. remove the frame: its variables disappear */
    call_depth--;
    frame_start = old_frame_start;
    var_count   = old_var_count;
    return result;
}

/* build a list value from [a, b, c]; checks every item has the right type */
Value build_list(Node *n) {
    List *list = malloc(sizeof(List));
    list->count = 0;
    for (Node *item = n->left; item != NULL; item = item->next) list->count++;
    list->items = malloc(sizeof(Value) * (list->count > 0 ? list->count : 1));

    int i = 0;
    for (Node *item = n->left; item != NULL; item = item->next) {
        Value v = eval(item);
        if (n->op == MIXTURE && v.type != V_FORMULA) {
            printf("line %d: a mixture can only hold formulas, but got %s: ", n->line, type_name(v));
            print_value(v);
            printf("\n");
            exit(1);
        }
        if (n->op == READINGS && v.type != V_NUM) {
            printf("line %d: readings can only hold numbers, but got %s: ", n->line, type_name(v));
            print_value(v);
            printf("\n");
            exit(1);
        }
        list->items[i++] = v;
    }
    return make_list(n->op == MIXTURE ? V_MIXTURE : V_READINGS, list);
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
    case N_LIST:    return build_list(n);

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

/* a condition must be a number: 0 = false, anything else = true */
int is_true(Node *cond) {
    return num_of(eval(cond), cond->line) != 0;
}

void exec(Node *n) {
    switch (n->type) {
    case N_ASSIGN:
        set_var(n->text, eval(n->left));
        break;

    case N_EQUATION:                                   /* store the equation as written */
        set_var(n->text, make_equation(n->eq));
        break;

    case N_CHECK: {                                    /* report: balanced or not */
        Equation *eq = n->eq ? n->eq : equation_of(eval(n->left), n->line);
        char text[1000], msg[1000], suggestion[1000];
        chem_equation_to_text(eq, text);
        if (chem_check(eq, msg, suggestion)) {
            printf("%s is balanced\n", text);
        } else {
            printf("%s is not balanced (%s)\n", text, msg);
            if (suggestion[0] == '(') printf("  it cannot be balanced\n");
            else                      printf("  balanced version: %s\n", suggestion);
        }
        break;
    }

    case N_EMIT: {
        /* first calculate every item, then print: if one item has an error,
           nothing of this line is printed                                    */
        int count = 0;
        for (Node *item = n->left; item != NULL; item = item->next) count++;
        Value *values = malloc(sizeof(Value) * count);
        int i = 0;
        for (Node *item = n->left; item != NULL; item = item->next) values[i++] = eval(item);
        for (i = 0; i < count; i++) {
            if (i > 0) printf(" ");                    /* space between items */
            print_value(values[i]);
        }
        printf("\n");
        free(values);
        break;
    }

    case N_OBSERVE:
        if (is_true(n->left)) exec_list(n->right);     /* condition true  */
        else                  exec_list(n->other);     /* condition false */
        break;

    case N_WHILE:
        while (!producing && is_true(n->left)) {       /* check condition, run body, repeat */
            exec_list(n->right);
        }
        break;

    case N_TITRATE: {
        double from = num_of(eval(n->left), n->line);  /* calculated once, before the loop */
        double to   = num_of(eval(n->right), n->line);
        for (double i = from; i <= to && !producing; i++) {
            set_var(n->text, make_num(i));             /* loop variable = 1, 2, 3 ...      */
            exec_list(n->other);
        }
        break;
    }

    case N_EACH: {                                     /* each c in lab { ... } */
        List *list = list_of(eval(n->left), n->line);
        for (int i = 0; i < list->count && !producing; i++) {
            set_var(n->text, list->items[i]);          /* c = next item */
            exec_list(n->right);
        }
        break;
    }

    case N_PRODUCE:
        if (call_depth == 0) {
            printf("line %d: produce can only be used inside a process\n", n->line);
            exit(1);
        }
        produced  = eval(n->left);
        producing = 1;                                 /* stop the rest of the process */
        break;

    case N_EXPR_STMT:                                  /* e.g. report(CO2);  value not used */
        eval(n->left);
        break;

    default:
        printf("line %d: unknown statement\n", n->line);
        exit(1);
    }
}

/* run every statement in a list, in order */
void exec_list(Node *list) {
    for (Node *n = list; n != NULL && !producing; n = n->next) {   /* stop after produce */
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
