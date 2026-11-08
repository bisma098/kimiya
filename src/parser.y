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

    /*data types/data structures*/
    N_NUM,       /* a number:          16              */
    N_STR,       /* a string:          "hello"         */
    N_FORMULA,   /* a formula:         H2O, Ca(OH)2    */
    N_REACTION,  /* one side ARROW other side: H2 + O2 -> H2O (used while parsing(temp)) */
    N_EQUATION,  /* equation water: H2 + O2 -> H2O;                      */
    N_VAR,       /* a variable:        fuel            */
    N_LIST,      /* a list:              mixture lab = [H2O, CO2];       */

    /*ops*/
    N_BINOP,     /* two-sided operator: a + b, a > b    */
    N_NEG,       /* negative:          -a              */
    N_ASSIGN,    /* assignment:        expr -> name;   */

    /*keywords*/
    N_EMIT,      /* print:             emit(a, b);     */
    N_OBSERVE,   /* if/else:           observe (c) {...} otherwise {...} */
    N_CHECK,     /* check water;  or  check 2 H2 + O2 -> 2 H2O;          */

    /*kinda loops*/
    N_WHILE,     /* while loop:        heat while (c) {...}              */
    N_TITRATE,   /* counting loop:     titrate g from 1 to 5 {...}       */
    N_EACH,       /* list loop:           each c in lab {...}             */

    /*functions*/
    N_CALL,      /* function call:     mass(H2O), moles(36, H2O)         */
    N_PROCESS,   /* function definition: process name(a, b) {...}        */
    N_PRODUCE,   /* return a value:      produce a + b;                  */

    N_EXPR_STMT, /* an expression used as a statement: report(CO2);   (like result not assigned to anything or not printed etc)  */
    
    
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
                               N_LIST: list of items   
                               N_EACH: the list   */

    struct Node *right;     /* N_BINOP: right side  
                               N_OBSERVE/N_WHILE: the block
                                N_EACH: the block 
                               N_TITRATE: end value
                               N_PROCESS: the body    
                               */

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

//none-terminals -> tree nodes
%type <node> stmts stmt block otherwise_part expr_list expr
%type <node> reaction side term
%type <node> params param_list list_items

//precedence: lower the line higher the precedence
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
        | IDENT '(' expr_list ')'       { $$ = new_call($1, $3); }  //func call
        | IDENT '(' ')'                 { $$ = new_call($1, NULL); }  //func call with no params
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
        | '-' expr %prec UMINUS         { $$ = new_neg($2); }       // %prec UMINUS : use UMINUS’s priority for this rule (the highest),
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

/* =====================================================================
   PART 4: THE COMPILER (Phase 2)
   Walks the SAME tree as Part 3, but instead of running it, it WRITES
   LLVM IR into a .ll file. clang then turns the .ll file into a program.
   Values in the compiled program are boxes (see src/runtime.c), so the
   IR passes around `ptr` values and calls kv_... functions on them.
   ===================================================================== */

FILE *ir;                   /* the .ll file being written */
const char *ir_path;        /* its name, so a half-written file can be deleted */

/* tell LLVM which runtime.c functions exist (like C prototypes) */
void write_declarations(void) {
    fprintf(ir, "; functions from src/runtime.c\n");
    fprintf(ir, "declare ptr  @kv_num(double)\n");
    fprintf(ir, "declare ptr  @kv_add(ptr, ptr, i32)\n");
    fprintf(ir, "declare ptr  @kv_sub(ptr, ptr, i32)\n");
    fprintf(ir, "declare ptr  @kv_mul(ptr, ptr, i32)\n");
    fprintf(ir, "declare ptr  @kv_div(ptr, ptr, i32)\n");
    fprintf(ir, "declare ptr  @kv_neg(ptr, i32)\n");
    fprintf(ir, "declare ptr  @kv_eq(ptr, ptr, i32)\n");
    fprintf(ir, "declare ptr  @kv_ne(ptr, ptr, i32)\n");
    fprintf(ir, "declare ptr  @kv_lt(ptr, ptr, i32)\n");
    fprintf(ir, "declare ptr  @kv_gt(ptr, ptr, i32)\n");
    fprintf(ir, "declare ptr  @kv_le(ptr, ptr, i32)\n");
    fprintf(ir, "declare ptr  @kv_ge(ptr, ptr, i32)\n");
    fprintf(ir, "declare ptr  @kv_str(ptr)\n");
    fprintf(ir, "declare ptr  @kv_formula(ptr)\n");
    fprintf(ir, "declare ptr  @kv_get(ptr, ptr, i32)\n");
    fprintf(ir, "declare i32  @kv_truth(ptr, i32)\n");
    fprintf(ir, "declare ptr  @kv_mass(ptr, i32)\n");
    fprintf(ir, "declare ptr  @kv_moles(ptr, ptr, i32)\n");
    fprintf(ir, "declare ptr  @kv_equation_new()\n");
    fprintf(ir, "declare void @kv_equation_add(ptr, i32, ptr, i32)\n");
    fprintf(ir, "declare void @kv_check(ptr, i32)\n");
    fprintf(ir, "declare ptr  @kv_balance(ptr, i32)\n");
    fprintf(ir, "declare ptr  @kv_yield(ptr, ptr, ptr, ptr, i32)\n");
    fprintf(ir, "declare ptr  @kv_need(ptr, ptr, ptr, ptr, i32)\n");
    fprintf(ir, "declare ptr  @kv_limiting(ptr, ptr, ptr, ptr, ptr, i32)\n");
    fprintf(ir, "declare ptr  @kv_product(ptr, ptr, ptr, ptr, ptr, ptr, i32)\n");
    fprintf(ir, "declare ptr  @kv_get_or(ptr, ptr, ptr, i32)\n");
    fprintf(ir, "declare ptr  @kv_produce_outside(i32)\n");
    fprintf(ir, "declare void @kv_enter(i32)\n");
    fprintf(ir, "declare void @kv_leave()\n");
    fprintf(ir, "declare ptr  @kv_list_new(i32, i32)\n");
    fprintf(ir, "declare void @kv_list_set(ptr, i32, ptr, i32)\n");
    fprintf(ir, "declare i32  @kv_list_count(ptr, i32)\n");
    fprintf(ir, "declare ptr  @kv_list_get(ptr, i32)\n");
    fprintf(ir, "declare ptr  @kv_count(ptr, i32)\n");
    fprintf(ir, "declare ptr  @kv_average(ptr, i32)\n");
    fprintf(ir, "declare void @kv_print(ptr)\n");
    fprintf(ir, "declare void @kv_print_space()\n");
    fprintf(ir, "declare void @kv_print_newline()\n");
    fprintf(ir, "\n");
}

/* ---------- registers ----------
   Every result in IR goes into a NEW numbered register (%1, %2, ...).
   new_reg() gives the next free number.                               */
int reg_count = 0;

int new_reg(void) {
    return ++reg_count;
}

/* ---------- labels ----------
   observe (and later loops) is made of several BLOCKS of code with names
   (labels) like then.3 or end.3. Each observe gets its own number, so the
   names never clash, even when one observe is inside another.          */
int label_count = 0;

int new_label(void) {
    return ++label_count;
}

int gen_expr(Node *n);      /* written further down; gen_condition needs it */

/* write IR that checks a condition; returns the register holding i1 (true/false) */
int gen_condition(Node *cond) {
    int v = gen_expr(cond);                            /* the box with the condition's value */
    int t = new_reg();
    fprintf(ir, "  %%%d = call i32 @kv_truth(ptr %%%d, i32 %d)\n", t, v, cond->line);
    int c = new_reg();
    fprintf(ir, "  %%%d = icmp ne i32 %%%d, 0\n", c, t);  /* int 1/0 -> i1 true/false */
    return c;
}

/* ---------- variables ----------
   Variables of the MAIN program are GLOBAL variables in the IR (@g.NAME), so
   that processes can read them too. They start as null (= no value yet).
   Variables of a PROCESS (its parameters and everything it assigns) are LOCAL:
   a slot made with `alloca` at the start of that function (%v.NAME).
   Assigning writes the slot (store), using it reads it (load).
   Before writing a function we walk its statements once to find its variables. */
#define MAX_COMPILED_VARS 500
char *global_vars[MAX_COMPILED_VARS];      /* variables of the main program */
int   global_var_count = 0;
char *local_vars[MAX_COMPILED_VARS];       /* variables of the process being compiled */
int   local_var_count = 0;
int   in_process = 0;                      /* 1 while a process is being compiled */

int in_list(char *list[], int count, char *name) {
    for (int i = 0; i < count; i++)
        if (strcmp(list[i], name) == 0) return 1;
    return 0;
}

void add_to_list(char *list[], int *count, char *name) {
    if (in_list(list, *count, name)) return;                  /* already known */
    if (*count == MAX_COMPILED_VARS) {
        printf("too many variables to compile\n");
        exit(1);
    }
    list[(*count)++] = name;
}

/* a variable that gets a value: global in main, local in a process */
void add_var(char *name) {
    if (in_process) add_to_list(local_vars, &local_var_count, name);
    else            add_to_list(global_vars, &global_var_count, name);
}

int is_local(char *name)  { return in_process && in_list(local_vars, local_var_count, name); }
int is_global(char *name) { return in_list(global_vars, global_var_count, name); }

/* the IR address of a variable's slot: "%v.x" (local) or "@g.x" (global) */
const char *slot(char *name) {
    static char buf[300];
    snprintf(buf, sizeof buf, is_local(name) ? "%%v.%s" : "@g.%s", name);
    return buf;
}

/* every variable name used anywhere, as text (@name.x), for error messages */
char *names[MAX_COMPILED_VARS];
int   name_count = 0;

void add_name(char *name) { add_to_list(names, &name_count, name); }

/* every titrate loop needs two hidden slots of its own: its counter and its end
   value. They are numbered 1, 2, 3 ... and the number is kept in the loop's node
   (in the `op` field, which titrate does not use otherwise).                   */
int titrate_count = 0;

/* find every variable that gets a value somewhere in these statements */
void collect_vars(Node *list) {
    for (Node *n = list; n != NULL; n = n->next) {
        switch (n->type) {
        case N_ASSIGN:   add_var(n->text); break;
        case N_EQUATION: add_var(n->text); break;
        case N_OBSERVE:  collect_vars(n->right); collect_vars(n->other); break;
        case N_WHILE:    collect_vars(n->right); break;
        case N_TITRATE:
            add_var(n->text);                          /* the loop variable, e.g. g */
            n->op = ++titrate_count;                   /* this loop's hidden slots  */
            collect_vars(n->other);
            break;
        case N_EACH:
            add_var(n->text);                          /* the loop variable, e.g. c */
            n->op = ++titrate_count;                   /* this loop's hidden slots  */
            collect_vars(n->right);
            break;
        default: break;
        }
    }
}

/* make the hidden slots of the titrate loops numbered first .. last */
void write_loop_slots(int first, int last) {
    for (int i = first; i <= last; i++) {
        fprintf(ir, "  %%loop.%d.counter = alloca ptr\n", i);
        fprintf(ir, "  %%loop.%d.end = alloca ptr\n", i);
        fprintf(ir, "  %%loop.%d.index = alloca i32\n", i);   /* used by each */
    }
}

/* ---------- text constants ----------
   Every string ("hello") and formula (H2O) in the program is written once,
   at the end of the .ll file, as a global constant @str.1, @str.2, ...
   The code refers to it by that name.                                     */
#define MAX_TEXTS 1000
char *texts[MAX_TEXTS];
int   text_count = 0;

/* returns the number N of the constant @str.N holding this text */
int add_text(char *text) {
    for (int i = 0; i < text_count; i++)
        if (strcmp(texts[i], text) == 0) return i + 1;        /* same text: reuse it */
    if (text_count == MAX_TEXTS) {
        printf("too many strings and formulas to compile\n");
        exit(1);
    }
    texts[text_count++] = text;
    return text_count;
}

/* write one text in LLVM's c"..." form. Letters, digits, spaces and most
   symbols are written as they are; anything else (like " or \) is written
   as \XX, its code in hexadecimal. \00 ends the text.                    */
void write_text_constant(const char *name, int number, const char *text) {
    fprintf(ir, "@%s.%d = private constant [%d x i8] c\"", name, number, (int)strlen(text) + 1);
    for (const char *c = text; *c; c++) {
        if (*c >= 32 && *c <= 126 && *c != '"' && *c != '\\') fputc(*c, ir);
        else fprintf(ir, "\\%02X", (unsigned char)*c);
    }
    fprintf(ir, "\\00\"\n");
}

/* stop if the compiler meets something it cannot compile yet */
void not_supported(Node *n, const char *what) {
    printf("line %d: the compiler does not support %s yet\n", n->line, what);
    fclose(ir);
    remove(ir_path);                /* do not leave a broken .ll file behind */
    exit(1);
}

/* ---------- function calls ----------
   A built-in function becomes one call to its kv_... function in runtime.c.
   The table says which runtime function, and how many values it needs.   */
typedef struct {
    const char *name;       /* name in Kimiya           */
    const char *runtime;    /* function in runtime.c    */
    int         args;       /* how many values it needs */
    const char *usage;      /* for the error message    */
} Builtin;

Builtin builtins[] = {
    { "mass",  "kv_mass",  1, "mass(formula)" },
    { "moles", "kv_moles", 2, "moles(grams, formula)" },
    { "balance", "kv_balance", 1, "balance(equation)" },
    { "yield",    "kv_yield",    4, "yield(equation, reactant, grams, product)" },
    { "need",     "kv_need",     4, "need(equation, reactant, grams, other)" },
    { "limiting", "kv_limiting", 5, "limiting(equation, A, grams, B, grams)" },
    { "product",  "kv_product",  6, "product(equation, A, grams, B, grams, product)" },
    { "count",    "kv_count",    1, "count(list)" },
    { "average",  "kv_average",  1, "average(readings)" },
    { NULL, NULL, 0, NULL }
    
};

int gen_call(Node *n) {
    /* 1. write the IR for every value inside the brackets, keep the registers */
    int regs[10];
    int count = 0;
    for (Node *a = n->left; a != NULL; a = a->next) {
        if (count == 10) not_supported(n, "more than 10 values in one call");
        regs[count++] = gen_expr(a);
    }

    /* 2a. a process written by the user: call its LLVM function @proc.NAME */
    Node *proc = find_process(n->text);
    if (proc != NULL) {
        int wanted = 0;
        for (Node *q = proc->left; q != NULL; q = q->next) wanted++;
        if (count != wanted) {
            printf("line %d: process %s() needs %d value(s) but got %d\n", n->line, n->text, wanted, count);
            fclose(ir);
            remove(ir_path);
            exit(1);
        }
        fprintf(ir, "  call void @kv_enter(i32 %d)\n", n->line);     /* count the depth */
        int r = new_reg();
        fprintf(ir, "  %%%d = call ptr @proc.%s(", r, n->text);
        for (int i = 0; i < count; i++) fprintf(ir, "%sptr %%%d", i > 0 ? ", " : "", regs[i]);
        fprintf(ir, ")\n");
        fprintf(ir, "  call void @kv_leave()\n");
        return r;
    }

    /* 2b. a built-in function: find it in the table */
    Builtin *b = NULL;
    for (int i = 0; builtins[i].name != NULL; i++)
        if (strcmp(builtins[i].name, n->text) == 0) b = &builtins[i];
    if (b == NULL) not_supported(n, "this function");

    /* the number of values is known now, so a wrong count is caught while compiling */
    if (count != b->args) {
        printf("line %d: %s() needs %d value(s): %s\n", n->line, n->text, b->args, b->usage);
        fclose(ir);
        remove(ir_path);
        exit(1);
    }

    /* 3. one call:  %r = call ptr @kv_mass(ptr %1, i32 LINE) */
    int r = new_reg();
    fprintf(ir, "  %%%d = call ptr @%s(", r, b->runtime);
    for (int i = 0; i < count; i++) fprintf(ir, "ptr %%%d, ", regs[i]);
    fprintf(ir, "i32 %d)\n", n->line);
    return r;
}
/* ---------- equations ----------
   The equation was already read while parsing (Part 1, to_equation), so the
   compiler knows every compound and coefficient. It writes IR that builds
   the same equation when the program runs:
       %1 = call ptr @kv_equation_new()
       call void @kv_equation_add(ptr %1, i32 0, ptr @str.1, i32 1)   ; left:  H2
       call void @kv_equation_add(ptr %1, i32 0, ptr @str.2, i32 1)   ; left:  O2
       call void @kv_equation_add(ptr %1, i32 1, ptr @str.3, i32 1)   ; right: H2O  */
int gen_equation(Equation *eq) {
    int r = new_reg();
    fprintf(ir, "  %%%d = call ptr @kv_equation_new()\n", r);
    for (int i = 0; i < eq->n_left; i++)
        fprintf(ir, "  call void @kv_equation_add(ptr %%%d, i32 0, ptr @str.%d, i32 %d)   ; left: %s\n",
                r, add_text(eq->left[i]), eq->left_coef[i], eq->left[i]);
    for (int i = 0; i < eq->n_right; i++)
        fprintf(ir, "  call void @kv_equation_add(ptr %%%d, i32 1, ptr @str.%d, i32 %d)   ; right: %s\n",
                r, add_text(eq->right[i]), eq->right_coef[i], eq->right[i]);
    return r;
}

/* ---------- expressions: write IR that makes a box, return its register ---------- */
int gen_expr(Node *n) {
    switch (n->type) {
    case N_NUM: {
        /* LLVM wants doubles written exactly; the safest way is the
           hexadecimal form of the 64 bits (16.0 -> 0x4030000000000000) */
        unsigned long long bits;
        memcpy(&bits, &n->num, sizeof bits);
        int r = new_reg();
        fprintf(ir, "  %%%d = call ptr @kv_num(double 0x%016llX)   ; %g\n", r, bits, n->num);
        return r;
    }
    case N_BINOP: {
        /* first the IR for both sides, then one call that combines them */
        int a = gen_expr(n->left);
        int b = gen_expr(n->right);
        const char *fn = "";
        switch (n->op) {
        case '+': fn = "kv_add"; break;
        case '-': fn = "kv_sub"; break;
        case '*': fn = "kv_mul"; break;
        case '/': fn = "kv_div"; break;
        case EQ:  fn = "kv_eq";  break;
        case NE:  fn = "kv_ne";  break;
        case '<': fn = "kv_lt";  break;
        case '>': fn = "kv_gt";  break;
        case LE:  fn = "kv_le";  break;
        case GE:  fn = "kv_ge";  break;
        }
        int r = new_reg();
        fprintf(ir, "  %%%d = call ptr @%s(ptr %%%d, ptr %%%d, i32 %d)\n", r, fn, a, b, n->line);
        return r;
    }
    case N_STR: {                                      /* "hello" */
        int r = new_reg();
        fprintf(ir, "  %%%d = call ptr @kv_str(ptr @str.%d)   ; \"%s\"\n", r, add_text(n->text), n->text);
        return r;
    }

    case N_FORMULA: {                                  /* H2O (already checked while parsing) */
        int r = new_reg();
        fprintf(ir, "  %%%d = call ptr @kv_formula(ptr @str.%d)   ; %s\n", r, add_text(n->text), n->text);
        return r;
    }
    case N_VAR: {
        add_name(n->text);
        if (is_local(n->text) && is_global(n->text)) {
            /* local AND global: use the local if it has a value, else the global */
            int a = new_reg();
            fprintf(ir, "  %%%d = load ptr, ptr %%v.%s\n", a, n->text);
            int b = new_reg();
            fprintf(ir, "  %%%d = load ptr, ptr @g.%s\n", b, n->text);
            int r = new_reg();
            fprintf(ir, "  %%%d = call ptr @kv_get_or(ptr %%%d, ptr %%%d, ptr @name.%s, i32 %d)\n",
                    r, a, b, n->text, n->line);
            return r;
        }
        if (is_local(n->text) || is_global(n->text)) {
            /* read the slot, then let the runtime check it has a value */
            int a = new_reg();
            fprintf(ir, "  %%%d = load ptr, ptr %s\n", a, slot(n->text));
            int r = new_reg();
            fprintf(ir, "  %%%d = call ptr @kv_get(ptr %%%d, ptr @name.%s, i32 %d)\n", r, a, n->text, n->line);
            return r;
        }
        /* a variable that never gets a value anywhere has no slot: pass null,
           so the program stops with "undefined variable" only IF this line runs */
        int r = new_reg();
        fprintf(ir, "  %%%d = call ptr @kv_get(ptr null, ptr @name.%s, i32 %d)\n", r, n->text, n->line);
        return r;
    }
    case N_CALL:                                       /* mass(H2O), moles(36, H2O) */
        return gen_call(n);
    
    case N_LIST: {                                     /* [H2O, CO2, NaCl] */
        int count = 0;
        for (Node *item = n->left; item != NULL; item = item->next) count++;
        int l = new_reg();
        fprintf(ir, "  %%%d = call ptr @kv_list_new(i32 %d, i32 %d)   ; %s\n",
                l, n->op == MIXTURE ? 0 : 1, count, n->op == MIXTURE ? "mixture" : "readings");
        int i = 0;
        for (Node *item = n->left; item != NULL; item = item->next, i++) {
            int x = gen_expr(item);                    /* calculate the item, then put it in */
            fprintf(ir, "  call void @kv_list_set(ptr %%%d, i32 %d, ptr %%%d, i32 %d)\n", l, i, x, n->line);
        }
        return l;
    }
    case N_NEG: {
        int a = gen_expr(n->left);
        int r = new_reg();
        fprintf(ir, "  %%%d = call ptr @kv_neg(ptr %%%d, i32 %d)\n", r, a, n->line);
        return r;
    }

    default:
        not_supported(n, "this kind of expression");
        return 0;
    }
}

/* ---------- statements: write IR that does the statement ---------- */
void gen_list(Node *list);  /* written further down; observe needs it for its blocks */

void gen_stmt(Node *n) {
    switch (n->type) {
    case N_EMIT: {
        /* first calculate every item (like the interpreter), then print them */
        int regs[100];
        int count = 0;
        for (Node *item = n->left; item != NULL; item = item->next) {
            if (count == 100) not_supported(n, "more than 100 values in one emit");
            regs[count++] = gen_expr(item);
        }
        for (int i = 0; i < count; i++) {
            if (i > 0) fprintf(ir, "  call void @kv_print_space()\n");
            fprintf(ir, "  call void @kv_print(ptr %%%d)\n", regs[i]);
        }
        fprintf(ir, "  call void @kv_print_newline()\n");
        break;
    }
    case N_OBSERVE: {
        /*   condition true?  --yes-->  then.N:  observe block    --+
                              --no--->  else.N:  otherwise block  --+-->  end.N   */
        int k = new_label();
        int c = gen_condition(n->left);
        fprintf(ir, "  br i1 %%%d, label %%then.%d, label %%else.%d\n", c, k, k);

        fprintf(ir, "then.%d:\n", k);
        gen_list(n->right);
        fprintf(ir, "  br label %%end.%d\n", k);

        fprintf(ir, "else.%d:\n", k);
        gen_list(n->other);                            /* nothing if there is no otherwise */
        fprintf(ir, "  br label %%end.%d\n", k);

        fprintf(ir, "end.%d:\n", k);
        break;
    }
    case N_WHILE: {
        /*   cond.N:  condition true?  --yes-->  body.N:  loop block,  then back to cond.N
                                       --no--->  done.N:  the rest of the program        */
        int k = new_label();
        fprintf(ir, "  br label %%cond.%d\n", k);

        fprintf(ir, "cond.%d:\n", k);                    /* checked again before every round */
        int c = gen_condition(n->left);
        fprintf(ir, "  br i1 %%%d, label %%body.%d, label %%done.%d\n", c, k, k);

        fprintf(ir, "body.%d:\n", k);
        gen_list(n->right);
        fprintf(ir, "  br label %%cond.%d\n", k);        /* jump BACK: repeat */

        fprintf(ir, "done.%d:\n", k);
        break;
    }

    case N_TITRATE: {
        /* titrate g from A to B { ... }
           like the interpreter: A and B are calculated ONCE, a hidden counter
           goes A, A+1, ... while counter <= B, and g gets the counter's value
           at the start of every round.                                      */
        int k = new_label();
        int s = n->op;                                 /* number of this loop's hidden slots */

        int a = gen_expr(n->left);                     /* start value */
        fprintf(ir, "  store ptr %%%d, ptr %%loop.%d.counter\n", a, s);
        int b = gen_expr(n->right);                    /* end value */
        fprintf(ir, "  store ptr %%%d, ptr %%loop.%d.end\n", b, s);
        fprintf(ir, "  br label %%cond.%d\n", k);

        /* cond: counter <= end ? */
        fprintf(ir, "cond.%d:\n", k);
        int x = new_reg();
        fprintf(ir, "  %%%d = load ptr, ptr %%loop.%d.counter\n", x, s);
        int y = new_reg();
        fprintf(ir, "  %%%d = load ptr, ptr %%loop.%d.end\n", y, s);
        int le = new_reg();
        fprintf(ir, "  %%%d = call ptr @kv_le(ptr %%%d, ptr %%%d, i32 %d)\n", le, x, y, n->line);
        int t = new_reg();
        fprintf(ir, "  %%%d = call i32 @kv_truth(ptr %%%d, i32 %d)\n", t, le, n->line);
        int c = new_reg();
        fprintf(ir, "  %%%d = icmp ne i32 %%%d, 0\n", c, t);
        fprintf(ir, "  br i1 %%%d, label %%body.%d, label %%done.%d\n", c, k, k);

        /* body: g = counter, run the block, counter = counter + 1, back to cond */
        fprintf(ir, "body.%d:\n", k);
        int cur = new_reg();
        fprintf(ir, "  %%%d = load ptr, ptr %%loop.%d.counter\n", cur, s);
        fprintf(ir, "  store ptr %%%d, ptr %s\n", cur, slot(n->text));
        gen_list(n->other);
        int now = new_reg();
        fprintf(ir, "  %%%d = load ptr, ptr %%loop.%d.counter\n", now, s);
        int one = new_reg();
        fprintf(ir, "  %%%d = call ptr @kv_num(double 0x3FF0000000000000)   ; 1\n", one);
        int next = new_reg();
        fprintf(ir, "  %%%d = call ptr @kv_add(ptr %%%d, ptr %%%d, i32 %d)\n", next, now, one, n->line);
        fprintf(ir, "  store ptr %%%d, ptr %%loop.%d.counter\n", next, s);
        fprintf(ir, "  br label %%cond.%d\n", k);        /* jump BACK: repeat */

        fprintf(ir, "done.%d:\n", k);
        break;
    }

    case N_EQUATION: {                                 /* equation water: H2 + O2 -> H2O; */
        int r = gen_equation(n->eq);
        fprintf(ir, "  store ptr %%%d, ptr %s\n", r, slot(n->text));
        break;
    }

    case N_CHECK: {                                    /* check water;  or  check H2 + O2 -> H2O; */
        int r = n->eq ? gen_equation(n->eq) : gen_expr(n->left);
        fprintf(ir, "  call void @kv_check(ptr %%%d, i32 %d)\n", r, n->line);
        break;
    }

    case N_EACH: {
        /* each c in lab { ... }
           like the interpreter: the list is calculated ONCE, a hidden position
           goes 0, 1, 2 ... while position < number of items, and c gets item
           number `position` at the start of every round.                    */
        int k = new_label();
        int s = n->op;                                 /* number of this loop's hidden slots */

        int l = gen_expr(n->left);                     /* the list */
        int cnt = new_reg();                           /* also checks it IS a list */
        fprintf(ir, "  %%%d = call i32 @kv_list_count(ptr %%%d, i32 %d)\n", cnt, l, n->line);
        fprintf(ir, "  store ptr %%%d, ptr %%loop.%d.end\n", l, s);
        fprintf(ir, "  store i32 0, ptr %%loop.%d.index\n", s);
        fprintf(ir, "  br label %%cond.%d\n", k);

        /* cond: position < count ?   (plain integers: real IR maths, no boxes) */
        fprintf(ir, "cond.%d:\n", k);
        int i = new_reg();
        fprintf(ir, "  %%%d = load i32, ptr %%loop.%d.index\n", i, s);
        int c = new_reg();
        fprintf(ir, "  %%%d = icmp slt i32 %%%d, %%%d\n", c, i, cnt);
        fprintf(ir, "  br i1 %%%d, label %%body.%d, label %%done.%d\n", c, k, k);

        /* body: c = item number position, run the block, position + 1, back to cond */
        fprintf(ir, "body.%d:\n", k);
        int pos = new_reg();
        fprintf(ir, "  %%%d = load i32, ptr %%loop.%d.index\n", pos, s);
        int lst = new_reg();
        fprintf(ir, "  %%%d = load ptr, ptr %%loop.%d.end\n", lst, s);
        int item = new_reg();
        fprintf(ir, "  %%%d = call ptr @kv_list_get(ptr %%%d, i32 %%%d)\n", item, lst, pos);
        fprintf(ir, "  store ptr %%%d, ptr %s\n", item, slot(n->text));
        gen_list(n->right);
        int now = new_reg();
        fprintf(ir, "  %%%d = load i32, ptr %%loop.%d.index\n", now, s);
        int next = new_reg();
        fprintf(ir, "  %%%d = add i32 %%%d, 1\n", next, now);
        fprintf(ir, "  store i32 %%%d, ptr %%loop.%d.index\n", next, s);
        fprintf(ir, "  br label %%cond.%d\n", k);        /* jump BACK: repeat */

        fprintf(ir, "done.%d:\n", k);
        break;
    }

    case N_PRODUCE: {                                  /* produce value; */
        int r = gen_expr(n->left);
        if (!in_process) {                             /* in main: error only if it runs */
            int e = new_reg();
            fprintf(ir, "  %%%d = call ptr @kv_produce_outside(i32 %d)\n", e, n->line);
            break;
        }
        fprintf(ir, "  ret ptr %%%d\n", r);              /* leave the function with this value */
        fprintf(ir, "after.%d:\n", new_label());       /* code after a ret needs a new block */
        break;
    }

    case N_EXPR_STMT:                                  /* report(CO2);  the value is not used */
        gen_expr(n->left);
        break;

    case N_ASSIGN: {                                   /* value -> name; */
        int r = gen_expr(n->left);
        fprintf(ir, "  store ptr %%%d, ptr %s\n", r, slot(n->text));
        break;
    }
    default:
        not_supported(n, "this kind of statement");
    }
}

void gen_list(Node *list) {
    for (Node *n = list; n != NULL; n = n->next) {
        if (n->type == N_EMIT || n->type == N_ASSIGN || n->type == N_EQUATION ||
            n->type == N_CHECK || n->type == N_PRODUCE || n->type == N_EXPR_STMT)     
            fprintf(ir, "\n  ; line %d\n", n->line);
            gen_stmt(n);
    }
}
/* write one process as an LLVM function:
       define ptr @proc.NAME(ptr %p.a, ptr %p.b) { ... }
   It gets its own local variables and its own register numbers.        */
void compile_process(Node *proc) {
    in_process = 1;
    local_var_count = 0;
    reg_count = 0;                                     /* numbering starts again in every function */

    /* parameters and every variable the body assigns are local */
    for (Node *q = proc->left; q != NULL; q = q->next) add_var(q->text);
    int first_loop = titrate_count + 1;
    collect_vars(proc->right);
    int last_loop = titrate_count;

    fprintf(ir, "\ndefine ptr @proc.%s(", proc->text);
    int i = 0;
    for (Node *q = proc->left; q != NULL; q = q->next, i++)
        fprintf(ir, "%sptr %%p.%s", i > 0 ? ", " : "", q->text);
    fprintf(ir, ") {\n");
    fprintf(ir, "entry:\n");
    fprintf(ir, "  ; one slot per local variable, empty (null) at the start\n");
    for (i = 0; i < local_var_count; i++) {
        fprintf(ir, "  %%v.%s = alloca ptr\n", local_vars[i]);
        fprintf(ir, "  store ptr null, ptr %%v.%s\n", local_vars[i]);
    }
    write_loop_slots(first_loop, last_loop);
    fprintf(ir, "  ; the parameters get the values the caller passed\n");
    for (Node *q = proc->left; q != NULL; q = q->next)
        fprintf(ir, "  store ptr %%p.%s, ptr %%v.%s\n", q->text, q->text);

    gen_list(proc->right);                             /* the body */

    /* reaching the end without produce: the process gives 0 (like the interpreter) */
    int r = new_reg();
    fprintf(ir, "  %%%d = call ptr @kv_num(double 0x0000000000000000)   ; no produce -> 0\n", r);
    fprintf(ir, "  ret ptr %%%d\n", r);
    fprintf(ir, "}\n");
    in_process = 0;
}

void compile_program(Node *program, const char *source, const char *path) {
    ir_path = path;
    ir = fopen(path, "w");
    if (ir == NULL) {
        printf("cannot write %s\n", path);
        exit(1);
    }

    fprintf(ir, "; %s: compiled by Kimiya from %s\n\n", path, source);
    write_declarations();

    /* 1. main: its variables become global variables */
    collect_vars(program);
    int main_loops = titrate_count;
    fprintf(ir, "define i32 @main() {\n");
    fprintf(ir, "entry:\n");
    write_loop_slots(1, main_loops);
    gen_list(program);                                 /* the statements of the program */
    fprintf(ir, "  ret i32 0\n");
    fprintf(ir, "}\n");

    /* 2. every process becomes its own function */
    for (int i = 0; i < process_count; i++) compile_process(processes[i]);

    /* 3. the global variables of main, empty (null) at the start */
    fprintf(ir, "\n; variables of the main program\n");
    for (int i = 0; i < global_var_count; i++)
        fprintf(ir, "@g.%s = global ptr null\n", global_vars[i]);

    /* 4. every string and formula used in the program */
    fprintf(ir, "\n; strings and formulas\n");
    for (int i = 0; i < text_count; i++) write_text_constant("str", i + 1, texts[i]);

    /* 5. the name of every variable as text, for "undefined variable" errors */
    fprintf(ir, "\n; variable names\n");
    for (int i = 0; i < name_count; i++)
        fprintf(ir, "@name.%s = private constant [%d x i8] c\"%s\\00\"\n",
                names[i], (int)strlen(names[i]) + 1, names[i]);

    fclose(ir);
}

/* "tests/test2.kim" -> "tests/test2.ll" */
char *ll_name(const char *source) {
    char *path = malloc(strlen(source) + 4);
    strcpy(path, source);
    char *dot = strrchr(path, '.');
    if (dot != NULL && strchr(dot, '/') == NULL) *dot = 0;   /* remove ".kim" */
    strcat(path, ".ll");
    return path;
}

/* ---------- main ----------
   ./kimiya file.kim       Phase 1: interpret (run the tree)
   ./kimiya -c file.kim    Phase 2: compile (write file.ll)            */
int main(int argc, char *argv[]) {
    int compile = 0;
    char *source;

    if (argc == 2) {
        source = argv[1];
    } else if (argc == 3 && strcmp(argv[1], "-c") == 0) {
        compile = 1;
        source = argv[2];
    } else {
        printf("usage: ./kimiya file.kim       (run it)\n");
        printf("       ./kimiya -c file.kim    (compile it to LLVM IR)\n");
        return 1;
    }

    yyin = fopen(source, "r");
    if (yyin == NULL) {
        printf("cannot open %s\n", source);
        return 1;
    }

    if (yyparse() != 0) return 1;   /* 1. read the whole program and build the tree */
    fclose(yyin);

    if (compile) {                  /* 2a. Phase 2: write the tree as LLVM IR */
        char *path = ll_name(source);
        compile_program(root, source, path);
        printf("wrote %s\n", path);
    } else {                        /* 2b. Phase 1: run the tree */
        exec_list(root);
    }
    return 0;
}