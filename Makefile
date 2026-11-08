# Makefile for Kimiya
#   make                     build ./kimiya (the interpreter and the compiler)
#   make test                Phase 1 tests: interpreter output vs tests/expected
#   make test-compiler       Phase 2 tests: compiled program output vs interpreter output
#   make test-chem           test chem.c on its own
#   make run FILE=prog.kim   Phase 2: compile prog.kim to an executable and run it
#   make clean               delete kimiya, the generated C files, the .ll files, test_program and test_chem

kimiya: src/parser.y src/lexer.l src/chem.c src/chem.h
	bison -d src/parser.y
	flex src/lexer.l
	gcc parser.tab.c lex.yy.c src/chem.c -Isrc -o kimiya

test: kimiya
	bash run_tests.sh

# compile every test program, link it with clang, run it, and compare with the interpreter
test-compiler: kimiya
	@pass=0; fail=0; \
	for f in tests/*.kim tests/*/*.kim; do \
	    expected=$$(./kimiya "$$f" 2>&1); \
	    actual=$$(./kimiya -c "$$f" 2>&1) && \
	    clang -Wno-override-module "$${f%.kim}.ll" src/runtime.c src/chem.c -Isrc -o test_program && \
	    actual=$$(./test_program 2>&1); \
	    if [ "$$actual" = "$$expected" ]; then echo "PASS    $$f"; pass=$$((pass + 1)); \
	    else echo "FAIL    $$f"; fail=$$((fail + 1)); fi; \
	done; \
	echo "----- $$pass passed, $$fail failed -----"; \
	[ $$fail -eq 0 ]

test-chem:
	gcc tests/test_chem.c src/chem.c -Isrc -o test_chem
	./test_chem

run: kimiya
	bash kc.sh $(FILE)

clean:
	rm -f kimiya parser.tab.c parser.tab.h lex.yy.c
	rm -f test_program test_chem tests/*.ll tests/*/*.ll

.PHONY: test test-compiler test-chem run clean
