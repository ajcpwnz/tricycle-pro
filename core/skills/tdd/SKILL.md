---
name: tdd
description: >
  Red-Green-Refactor test-driven development workflow. Guides the agent
  through writing failing tests first, then implementing code to pass
  them, then refactoring while keeping tests green.
---

# TDD Skill

## When to use this Skill

Use this Skill when you are:

- Implementing a new feature using test-driven development
- Adding test coverage to existing untested code
- Refactoring code while maintaining correctness via tests
- Working on a project that requires TDD as part of its workflow

## The Red-Green-Refactor Cycle

### 1. Red — Write a Failing Test

- Write the smallest test that expresses the next piece of desired behavior
- Run the test and confirm it fails for the expected reason
- The test should fail because the feature is not yet implemented, not because of a syntax or setup error
- Name the test to describe the behavior being tested, not the implementation

### 2. Green — Make the Test Pass

- Write the minimum code necessary to make the failing test pass
- Do not write more code than needed — just enough to turn the test green
- Avoid the temptation to implement the "full" solution
- Run all tests to verify nothing else broke

### 3. Refactor — Clean Up

- Now that tests are green, improve the code structure
- Remove duplication, clarify names, simplify logic
- Run all tests after each refactoring step to confirm they still pass
- Do not add new behavior during refactoring — that requires a new Red step

## Guidelines

- **One behavior per test**: Each test should verify one specific aspect
- **Fast feedback**: Tests should run quickly; mock external dependencies if needed
- **Descriptive names**: Test names should read like specifications
- **Test the interface, not the implementation**: Tests should survive refactoring
- **Commit after each Green step**: Small, frequent commits with passing tests

## Things to Avoid

- Writing multiple tests before implementing any code
- Writing implementation code before having a failing test
- Skipping the refactor step when tests pass
- Testing private implementation details instead of public behavior
- Writing tests so tightly coupled to implementation that any refactor breaks them
