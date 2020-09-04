Require Import ZArith.
Require Import Coq.Lists.List coqutil.Datatypes.List.
Require Import coqutil.Map.Interface coqutil.Map.OfFunc.
Import Interface.map MapKeys.map OfFunc.map.
Require Import coqutil.Word.Interface coqutil.Word.Properties.

Module map.
  Section __.
    Context {width} {word : word width} {word_ok : word.ok word}.
    Add Ring __wring: (@word.ring_theory width word word_ok).
    Context {value : Type} {map : map word value} {ok : map.ok map}.

    Definition of_list_word (xs : list value) : map :=
      map.of_func
      (fun w => nth_error xs (Z.to_nat (word.unsigned w)))
      (List.map (fun n => word.of_Z (Z.of_nat n)) (seq 0 (length xs))).
    Definition of_list_word_at (a : word) (xs : list value) : map :=
      map_keys (word.add a) (of_list_word xs).
    Lemma get_of_list_word xs i : get (of_list_word xs) i
      = nth_error xs (Z.to_nat (word.unsigned i)).
    Proof.
      pose proof word.eqb_spec.
      cbv [of_list_word].
      erewrite get_of_func_Some_supported; trivial; intros.
      pose proof word.unsigned_range k.
      eapply in_map_iff; exists (Z.to_nat (word.unsigned k));
        rewrite ?in_seq; repeat split; rewrite ?Znat.Z2Nat.id;
        try Lia.lia; try solve [eapply word.of_Z_unsigned].
      apply nth_error_Some. congruence.
    Qed.
    Lemma get_of_list_word_at a xs i : get (of_list_word_at a xs) i
      = nth_error xs (Z.to_nat (word.unsigned (word.sub i a))).
    Proof.
      cbv [of_list_word_at].
      replace i with (word.add a (word.sub i a)) by ring.
      rewrite get_map_keys_always_invertible, get_of_list_word.
      2: { intros ? ? H.
           assert (A:word.sub (word.add a k) a = word.sub (word.add a k') a).
           { rewrite H; trivial. }
           ring_simplify in A; exact A. }
      f_equal. f_equal. f_equal. ring.
    Qed.

    Lemma get_of_list_word_at_domain a xs i :
      get (of_list_word_at a xs) i <> None
      <->
      (0 <= word.unsigned (word.sub i a) < Z.of_nat (length xs))%Z.
    Proof.
      pose proof word.unsigned_range (word.sub i a).
      rewrite get_of_list_word_at, nth_error_Some.
      rewrite Nat2Z.inj_lt, ?Znat.Z2Nat.id; intuition.
    Qed.
  End __.
End map.