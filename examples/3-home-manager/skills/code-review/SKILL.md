---
name: code-review
description: Code review guidelines and quality standards
tags: [code-quality, review]
---

# Code Review Guidelines

Standards for reviewing code across all projects.

## What We Review

- **Readability** — Is the code clear and understandable?
- **Correctness** — Does it do what it's supposed to do?
- **Performance** — Any obvious inefficiencies?
- **Security** — Vulnerabilities or risky patterns?
- **Tests** — Adequate coverage for changes?

## Code Clarity

### Good Code
- Descriptive variable names
- Functions do one thing
- Comments explain "why", not "what"
- Consistent formatting

### Common Issues

| Issue | Example | Fix |
|-------|---------|-----|
| Unclear names | `x = y + z` | `totalPrice = itemCost + tax` |
| Deep nesting | 5+ levels of `if` | Extract functions, use guards |
| Magic numbers | `if (age > 18)` | `const ADULT_AGE = 18` |
| Long functions | 100+ line function | Break into smaller functions |
| Missing tests | Critical logic without tests | Add comprehensive tests |

## Performance Red Flags

- N+1 queries (loop with DB calls inside)
- Unnecessary data copies in loops
- Blocking operations on main thread
- Regular expressions without optimization

## Security Checklist

- [ ] Input validation on user data
- [ ] No hardcoded secrets
- [ ] SQL queries use parameterized queries
- [ ] Auth/authorization checks present
- [ ] Error messages don't leak sensitive info
- [ ] Dependencies checked for vulnerabilities

## Approval Criteria

Approve when:
- ✅ Code meets standards
- ✅ Tests are adequate
- ✅ No security issues
- ✅ Performance acceptable
- ✅ Documentation clear

Request changes when:
- ❌ Readability concerns
- ❌ Missing tests
- ❌ Security issues
- ❌ Performance degradation
- ❌ Breaking changes undocumented
