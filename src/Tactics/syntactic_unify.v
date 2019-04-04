Require Import coqutil.Tactics.rdelta.

Ltac _syntactic_unify x y :=
  match constr:(Set) with
  | _ => is_evar x; unify x y
  | _ => is_evar y; unify x y
  | _ => lazymatch x with
         | ?f ?a => lazymatch y with ?g ?b => _syntactic_unify f g; _syntactic_unify a b end
         | (fun (a:?Ta) => ?f a)
           => lazymatch y with (fun (b:?Tb) => ?g b) =>
                               let __ := constr:(fun (a:Ta) (b:Tb) => ltac:(_syntactic_unify f g; exact Set)) in idtac end
         | let a : ?Ta := ?v in ?f a
           => lazymatch y with let b : ?Tb := ?w in ?g b =>
                               _syntactic_unify v w;
                               let __ := constr:(fun (a:Ta) (b:Tb) => ltac:(_syntactic_unify f g; exact Set)) in idtac end
         (* TODO: fail fast in more cases *)
         | _ => unify x y; constr_eq x y
         end
  end.
Tactic Notation "syntactic_unify" open_constr(x) open_constr(y) :=  _syntactic_unify x y.

Ltac _syntactic_unify_deltavar X Y :=
  let x := rdelta_var X in
  let y := rdelta_var Y in
  match constr:(Set) with
  | _ => is_evar x; unify x y
  | _ => is_evar y; unify x y
  | _ => lazymatch x with
         | ?f ?a => lazymatch y with ?g ?b => _syntactic_unify_deltavar f g; _syntactic_unify_deltavar a b end
         | (fun (a:?Ta) => ?f a)
           => lazymatch y with (fun (b:?Tb) => ?g b) =>
                               let __ := constr:(fun (a:Ta) (b:Tb) => ltac:(_syntactic_unify_deltavar f g; exact Set)) in idtac end
         | let a : ?Ta := ?v in ?f a
           => lazymatch y with let b : ?Tb := ?w in ?g b =>
                               _syntactic_unify_deltavar v w;
                               let __ := constr:(fun (a:Ta) (b:Tb) => ltac:(_syntactic_unify_deltavar f g; exact Set)) in idtac end
         (* TODO: fail fast in more cases *)
         | _ => unify X Y; constr_eq x y
         end
  end.
Tactic Notation "syntactic_unify_deltavar" open_constr(x) open_constr(y) :=  _syntactic_unify_deltavar x y.

Ltac _syntactic_exact e :=
  let t := type of e in
  let g := lazymatch goal with |- ?g => g end in
  tryif syntactic_unify t g then exact_no_check e else fail "syntactic_unify" t g.
Tactic Notation "syntactic_exact" open_constr(e) :=
  _syntactic_exact e.

Ltac _syntactic_exact_deltavar e :=
  let t := type of e in
  let g := lazymatch goal with |- ?g => g end in
  tryif syntactic_unify_deltavar t g then exact_no_check e else fail "syntactic_unify" t g.
Tactic Notation "syntactic_exact_deltavar" open_constr(e) :=
  _syntactic_exact_deltavar e.