extends RigidBody3D
## One brick. Everything in a built structure is made of these.
##
## Deliberately almost empty at C0. What a brick *is made of* — and therefore what happens
## when you hit it — arrives with materials in C1 and their behaviour in C5
## (`MATERIAL-SPEC`). There is no hit-point number here and there never will be: what
## happens to a thing is decided by what it's made of, not by a counter on the object.

## Set in C1 from the part table. Until then everything is untyped and behaves the same.
var material_id: StringName = &""
