---
name: create-oodz-class
description: Create or modify NX domain classes using the OODZ framework. Use for nx::Class, OODZ base objects, domain properties, and client business classes.
---

# Create an OODZ class

1. Read the closest project or module instructions.
2. Use `oodz_lookup` to locate the appropriate superclass.
3. Use `oodz_read` only for the selected framework class.
4. Inspect at most one similar class in the client project.
5. Use `nx::Class` and preserve existing namespace and naming conventions.
6. Use `:property` for object properties.
7. Call `next` from `init` unless the superclass documentation says otherwise.
8. Make the smallest necessary change.
9. Report whether the class was executed or only inspected.
