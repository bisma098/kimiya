CC     = gcc
CFLAGS = -Wall -g -Isrc -Ibuild

SRCS = src/ast.c src/eval.c src/chem.c src/main.c
GEN  = build/parser.tab.c build/lex.yy.c

kimiya: $(SRCS) $(GEN)
	$(CC) $(CFLAGS) $(SRCS) $(GEN) -o kimiya

build/parser.tab.c build/parser.tab.h: src/parser.y
	@mkdir -p build
	bison -d -Wcounterexamples -o build/parser.tab.c src/parser.y

build/lex.yy.c: src/lexer.l build/parser.tab.h
	@mkdir -p build
	flex -o build/lex.yy.c src/lexer.l

test: kimiya
	./kimiya tests/hello.kim

clean:
	rm -rf build kimiya

.PHONY: test clean
