# Makefile for Kimiya, a chemistry-aware programming language
#
#   make                         build the ./kimiya program (interpreter + compiler)
#   make test                    Phase 1 tests: interpreter output vs tests/expected
#   make test-compiler           Phase 2 tests: compiled program output vs interpreter output
#   make test-chem               test the chemistry library (chem.c) on its own
#   make test-all                all of the above
#   make compile FILE=prog.kim   Phase 2: prog.kim -> prog.ll -> executable ./prog
#   make run FILE=prog.kim       same as compile, then run the executable
#   make check-deps              check that bison, flex, gcc and clang are installed
#   make clean                   delete everything that make generated
#
# Generated files (parser.tab.c, parser.tab.h, lex.yy.c) go into build/,
# so src/ only ever contains the files we wrote ourselves.

CC     = gcc
CLANG  = clang
BISON  = bison
FLEX   = flex

BUILD  = build

# -Ibuild finds the parser.tab.h that Bison generates, -Isrc finds chem.h
CFLAGS = -I$(BUILD) -Isrc

# clang warns that it replaces the target triple of the .ll file with the
# one of this machine. That is expected, so the warning is switched off.
CLANGFLAGS = -Wno-override-module -Isrc

# C files that every compiled Kimiya program is linked with
RUNTIME = src/runtime.c src/chem.c

# every test program, used by test-compiler and clean
KIM_FILES = $(wildcard tests/*.kim tests/examples/*.kim tests/errors/*.kim tests/compile/*.kim)

.PHONY: all test test-compiler test-chem test-all compile run check-deps clean

# delete a half-written target if a command fails
.DELETE_ON_ERROR:


# ---------------------------------------------------------------------
# Building ./kimiya
# ---------------------------------------------------------------------

all: kimiya

# 3. compile and link the generated C files with the chemistry library
kimiya: $(BUILD)/parser.tab.c $(BUILD)/lex.yy.c src/chem.c src/chem.h
	$(CC) $(CFLAGS) $(BUILD)/parser.tab.c $(BUILD)/lex.yy.c src/chem.c -o kimiya

# 1. Bison: grammar -> parser in C (-d also writes parser.tab.h with the token numbers)
$(BUILD)/parser.tab.c: src/parser.y src/chem.h | $(BUILD)
	$(BISON) -d -o $(BUILD)/parser.tab.c src/parser.y

$(BUILD)/parser.tab.h: $(BUILD)/parser.tab.c

# 2. Flex: token rules -> scanner in C (needs the token numbers from parser.tab.h)
$(BUILD)/lex.yy.c: src/lexer.l $(BUILD)/parser.tab.h | $(BUILD)
	$(FLEX) -o $(BUILD)/lex.yy.c src/lexer.l

$(BUILD):
	mkdir -p $(BUILD)


# ---------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------

# Phase 1: run every test with the interpreter and compare with tests/expected
test: kimiya
	bash run_tests.sh

# Phase 2: compile every test program to LLVM IR, link it with clang, run it,
# and check that it prints exactly what the interpreter prints.
# Programs with an error found while parsing (e.g. an unknown element) give no
# .ll file; for those the error message of -c is compared instead.
test-compiler: kimiya | $(BUILD)
	@pass=0; fail=0; \
	for f in $(KIM_FILES); do \
	    expected=$$(./kimiya "$$f" 2>&1); \
	    if actual=$$(./kimiya -c "$$f" 2>&1); then \
	        if $(CLANG) $(CLANGFLAGS) "$${f%.kim}.ll" $(RUNTIME) -o $(BUILD)/test_program 2>$(BUILD)/clang_errors.txt; then \
	            actual=$$(./$(BUILD)/test_program 2>&1); \
	        else \
	            actual="clang failed: $$(head -3 $(BUILD)/clang_errors.txt)"; \
	        fi; \
	    fi; \
	    if [ "$$actual" = "$$expected" ]; then \
	        echo "PASS    $$f"; pass=$$((pass + 1)); \
	    else \
	        echo "FAIL    $$f"; \
	        echo "  interpreter: $$expected" | head -5; \
	        echo "  compiled:    $$actual" | head -5; \
	        fail=$$((fail + 1)); \
	    fi; \
	done; \
	echo "----- $$pass passed, $$fail failed -----"; \
	[ $$fail -eq 0 ]

# chem.c on its own, without Flex or Bison
test-chem: | $(BUILD)
	$(CC) -Isrc tests/test_chem.c src/chem.c -o $(BUILD)/test_chem
	./$(BUILD)/test_chem

test-all: test test-compiler test-chem


# ---------------------------------------------------------------------
# Compiling one program (Phase 2)
# ---------------------------------------------------------------------

# make compile FILE=tests/examples/ex5_volcano.kim
#   -> tests/examples/ex5_volcano.ll   (LLVM IR, written by ./kimiya -c)
#   -> tests/examples/ex5_volcano      (the executable, made by clang)
EXE = $(basename $(FILE))

compile: kimiya
	@if [ -z "$(FILE)" ]; then echo "usage: make compile FILE=program.kim"; exit 1; fi
	./kimiya -c $(FILE)
	$(CLANG) $(CLANGFLAGS) $(EXE).ll $(RUNTIME) -o $(EXE)
	@echo "executable: $(EXE)"

# a relative path needs ./ in front to run it, an absolute path does not
run: compile
	@case "$(EXE)" in /*) $(EXE) ;; *) ./$(EXE) ;; esac


# ---------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------

check-deps:
	@missing=0; \
	for tool in $(BISON) $(FLEX) $(CC) $(CLANG) bash; do \
	    if command -v $$tool >/dev/null 2>&1; then \
	        echo "found     $$tool: $$($$tool --version 2>&1 | head -1)"; \
	    else \
	        echo "MISSING   $$tool"; missing=1; \
	    fi; \
	done; \
	if [ $$missing -eq 1 ]; then echo "install with: sudo apt install build-essential bison flex clang"; exit 1; fi

# removes the program, build/, every .ll file, and the executables that
# `make compile` creates next to the test programs
clean:
	rm -rf kimiya $(BUILD)
	rm -f parser.tab.c parser.tab.h lex.yy.c
	rm -f $(KIM_FILES:.kim=.ll) $(KIM_FILES:.kim=)
