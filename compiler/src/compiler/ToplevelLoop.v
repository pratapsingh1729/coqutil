Require Export Coq.Lists.List.
Require Import Coq.ZArith.ZArith.
Export ListNotations.
Require Export coqutil.Decidable.
Require Import coqutil.Tactics.rewr.
Require        compiler.ExprImp.
Require Export compiler.FlattenExprDef.
Require Export compiler.FlattenExpr.
Require        compiler.FlatImp.
Require Export riscv.Spec.Decode.
Require Export riscv.Spec.Machine.
Require Export riscv.Platform.Run.
Require Export riscv.Platform.Minimal.
Require Export riscv.Platform.MetricLogging.
Require Export riscv.Utility.Monads.
Require Import riscv.Utility.runsToNonDet.
Require Export riscv.Platform.MetricRiscvMachine.
Require Import coqutil.Z.Lia.
Require Import compiler.NameGen.
Require Import compiler.StringNameGen.
Require Export compiler.util.Common.
Require Export coqutil.Decidable.
Require Export riscv.Utility.Encode.
Require Export riscv.Spec.Primitives.
Require Export riscv.Spec.MetricPrimitives.
Require Import compiler.GoFlatToRiscv.
Require Import riscv.Utility.MkMachineWidth.
Require Export riscv.Proofs.DecodeEncode.
Require Export riscv.Proofs.EncodeBound.
Require Export compiler.EmitsValid.
Require coqutil.Map.SortedList.
Require Import riscv.Utility.Utility.
Require Export riscv.Platform.Memory.
Require Export riscv.Utility.InstructionCoercions.
Require Import compiler.SeparationLogic.
Require Import compiler.Simp.
Require Import compiler.FlattenExprSimulation.
Require Import compiler.RegRename.
Require Import compiler.FlatToRiscvSimulation.
Require Import compiler.Simulation.
Require Import compiler.RiscvEventLoop.
Require Import bedrock2.MetricLogging.
Require Import compiler.FlatToRiscvCommon.
Require Import compiler.FlatToRiscvFunctions.
Require Import compiler.DivisibleBy4.
Require Import compiler.SimplWordExpr.
Require Import compiler.ForeverSafe.
Require Export compiler.MemoryLayout.
Require Import FunctionalExtensionality.
Require Import coqutil.Tactics.autoforward.
Require Import compiler.FitsStack.
Require Import compiler.PipelineWithRename.
Require Import compiler.ExprImpEventLoopSpec.

Existing Instance riscv.Spec.Machine.DefaultRiscvState.

Open Scope Z_scope.

Local Open Scope ilist_scope.

Local Notation "' x <- a ; f" :=
  (match (a: option _) with
   | x => f
   | _ => None
   end)
  (right associativity, at level 70, x pattern).

Local Axiom TODO_sam: False.

Section Pipeline1.

  Context {p: Pipeline.parameters}.
  Context {h: Pipeline.assumptions}.

  Context (ml: MemoryLayout)
          (mlOk: MemoryLayoutOk ml).

  Let init_sp := word.unsigned ml.(stack_pastend).

  Local Notation source_env := (@Pipeline.string_keyed_map p (list string * list string * Syntax.cmd)).

  (* All riscv machine code, layed out from low to high addresses:
     - init_sp_insts: initializes stack pointer
     - init_insts: calls init function
     - loop_insts: calls loop function
     - backjump_insts: jumps back to calling loop function
     - fun_insts: code of compiled functions *)
  Definition compile_prog(prog: source_env): option (list Instruction * funname_env Z) :=
    'Some (fun_insts, positions) <- @compile p ml prog;
    let init_sp_insts := FlatToRiscvDef.compile_lit RegisterNames.sp init_sp in
    'Some init_pos <- map.get positions "init"%string;
    'Some loop_pos <- map.get positions "loop"%string;
    let init_insts := [[Jal RegisterNames.ra (3 * 4 + init_pos)]] in
    let loop_insts := [[Jal RegisterNames.ra (2 * 4 + loop_pos)]] in
    let backjump_insts := [[Jal Register0 (-4*Z.of_nat (List.length loop_insts))]] in
    Some (init_sp_insts ++ init_insts ++ loop_insts ++ backjump_insts ++ fun_insts, positions).

  Context (spec: @ProgramSpec (FlattenExpr.mk_Semantics_params _)).

  Let loop_pos := word.add ml.(code_start)
         (word.of_Z (4 * (Z.of_nat (List.length (FlatToRiscvDef.compile_lit RegisterNames.sp init_sp))) + 4)).

  Axiom Rdata: mem -> Prop. (* maybe (emp True) will be fine *)
  Axiom Rexec: mem -> Prop. (* maybe (emp True) will be fine *)

  Definition ll_good(done: bool)(mach: MetricRiscvMachine): Prop :=
    exists (prog: source_env) (instrs: list Instruction) (positions: funname_env Z) (loop_fun_pos: Z),
      compile_prog prog = Some (instrs, positions) /\
      ProgramSatisfiesSpec "init"%string "loop"%string prog spec /\
      map.get positions "loop"%string = Some loop_fun_pos /\
      exists mH,
        isReady spec mach.(getLog) mH /\ goodTrace spec mach.(getLog) /\
        machine_ok ml.(code_start) loop_fun_pos ml.(stack_start) ml.(stack_pastend) instrs
                   loop_pos (word.add loop_pos (word.of_Z (if done then 4 else 0))) mH Rdata Rexec mach.

  Definition ll_inv: MetricRiscvMachine -> Prop := runsToGood_Invariant ll_good.

  Add Ring wring : (word.ring_theory (word := Utility.word))
      (preprocess [autorewrite with rew_word_morphism],
       morphism (word.ring_morph (word := Utility.word)),
       constants [word_cst]).

  Lemma compile_prog_to_compile: forall prog instrs positions,
      compile_prog prog = Some (instrs, positions) ->
      exists before main,
        compile ml prog = Some (main, positions) /\
        instrs = before ++ main.
  Proof.
    intros. unfold compile_prog in *. simp. do 2 eexists.
    split; [reflexivity|].
    match goal with
    | |- ?A ++ ?i1 :: ?i2 :: ?i3 :: ?B = ?R => change (A ++ [i1; i2; i3] ++ B = R)
    end.
    rewrite app_assoc.
    reflexivity.
  Qed.

  Definition initial_conditions(initial: MetricRiscvMachine): Prop :=
    exists (srcprog: source_env) (instrs: list Instruction) (positions: funname_env Z) (R: mem -> Prop),
      ProgramSatisfiesSpec "init"%string "loop"%string srcprog spec /\
      spec.(datamem_start) = ml.(heap_start) /\
      spec.(datamem_pastend) = ml.(heap_pastend) /\
      compile_prog srcprog = Some (instrs, positions) /\
      subset (footpr (program ml.(code_start) instrs)) (of_list initial.(getXAddrs)) /\
      (program ml.(code_start) instrs * R *
       mem_available ml.(heap_start) ml.(heap_pastend) *
       mem_available ml.(stack_start) ml.(stack_pastend))%sep initial.(getMem) /\
      initial.(getPc) = ml.(code_start) /\
      initial.(getNextPc) = word.add initial.(getPc) (word.of_Z 4) /\
      regs_initialized initial.(getRegs) /\
      initial.(getLog) = nil /\
      valid_machine initial.

  Lemma establish_ll_inv: forall (initial: MetricRiscvMachine),
      initial_conditions initial ->
      ll_inv initial.
  Proof.
    unfold initial_conditions.
    intros. simp.
    unfold ll_inv, runsToGood_Invariant.
    destruct_RiscvMachine initial.
    match goal with
    | H: context[ProgramSatisfiesSpec] |- _ => rename H into sat
    end.
    pose proof sat.
    destruct sat.
    match goal with
    | H: compile_prog srcprog = Some _ |- _ => pose proof H as CP; unfold compile_prog in H
    end.
    remember instrs as instrs0.
    simp.
    assert (map.ok mem) by exact mem_ok.
    assert (word.ok Semantics.word) by exact word_ok.
    eassert ((mem_available ml.(heap_start) ml.(heap_pastend) * _)%sep initial_mem) as SplitImem. {
      ecancel_assumption.
    }
    destruct SplitImem as [heap_mem [other_imem [SplitHmem [HMem OtherMem] ] ] ].
    (* first, run init_sp_code: *)
    pose proof FlatToRiscvLiterals.compile_lit_correct_full_raw as P.
    cbv zeta in P. (* needed for COQBUG https://github.com/coq/coq/issues/11253 *)
    specialize P with (x := RegisterNames.sp) (v := init_sp) (Rexec := emp True).
    unfold runsTo in P. eapply P; clear P; simpl.
    { assumption. }
    2: { wcancel_assumption. }
    {
      eapply shrink_footpr_subset. 1: eassumption.
      wwcancel.
    }
    { cbv. auto. }
    { assumption. }
    specialize init_code_correct with (mc0 := (bedrock2.MetricLogging.mkMetricLog 0 0 0 0)).
    assert (exists f_entry_rel_pos, map.get positions "init"%string = Some f_entry_rel_pos) as GetPos. {
      unfold compile, composePhases, renamePhase, flattenPhase, riscvPhase in *. simp.
      unfold flatten_functions, rename_functions, FlatToRiscvDef.function_positions in *.
      apply get_build_fun_pos_env.
      eapply (map.map_all_values_not_None_fw _ _ _ _ _ E3).
      unshelve eapply (map.map_all_values_not_None_fw _ _ _ _ _ E2).
      1, 2: simpl; typeclasses eauto.
      simpl in *. (* PARAMRECORDS *)
      congruence.
    }
    destruct GetPos as [f_entry_rel_pos GetPos].
    subst.
    (* then, run init_code (using compiler simulation and correctness of init_code) *)
    eapply runsTo_weaken.
    - pose proof compiler_correct as P. unfold runsTo in P.
      unfold ll_good.
      eapply P; clear P.
      6: {
        unfold hl_inv in init_code_correct.
        simpl.
        move init_code_correct at bottom.
        subst.
        refine (init_code_correct _ _).
        replace (datamem_start spec) with (heap_start ml) by congruence.
        replace (datamem_pastend spec) with (heap_pastend ml) by congruence.
        exact HMem.
      }
      all: try eassumption.
      unfold machine_ok.
      unfold_RiscvMachine_get_set.
      repeat match goal with
             | |- exists _, _  => eexists
             | |- _ /\ _ => split
             | |- _ => progress cbv beta iota
             | |- _ => eassumption
             | |- _ => reflexivity
             end.
      + case TODO_sam. (* verify Jal *)
      + (* TODO separation logic will instantiate p_functions to something <> ml.(code_start) *)
        case TODO_sam.
      + case TODO_sam.
      + destruct mlOk. solve_divisibleBy4.
      + solve_word_eq word_ok.
      + eapply @regs_initialized_put; try typeclasses eauto. (* PARAMRECORDS? *)
        eassumption.
      + rewrite map.get_put_same. unfold init_sp. rewrite word.of_Z_unsigned. reflexivity.
      + case TODO_sam. (* valid_machine preserved *)
    - cbv beta. unfold ll_good. intros. simp.
      repeat match goal with
             | |- exists _, _  => eexists
             | |- _ /\ _ => split
             | |- _ => progress cbv beta iota
             | |- _ => eassumption
             | |- _ => reflexivity
             end.
      + (* TODO fix memory layout (one which focuses on init instructions) *)
        case TODO_sam.
    Unshelve.
    all: intros; try exact True; try exact 0; try exact mem_ok; try apply @nil; try exact (word.of_Z 0).
  Qed.

  Lemma machine_ok_frame_instrs_app_l: forall p_code f_entry_rel_pos p_stack_start p_stack_pastend i1 i2
                                              p_call pc mH Rdata Rexec mach,
      machine_ok p_code f_entry_rel_pos p_stack_start p_stack_pastend (i1 ++ i2) p_call pc mH Rdata Rexec mach ->
      machine_ok p_code f_entry_rel_pos p_stack_start p_stack_pastend i2 p_call pc mH Rdata
                 (Rexec * program (word.add p_code (word.of_Z (4 * Z.of_nat (List.length i1))))i2)%sep
                 mach.
  Proof.
    unfold machine_ok.
    intros. simp.
    ssplit; eauto.
    all: case TODO_sam.
  Qed.

  Lemma ll_inv_is_invariant: forall (st: MetricRiscvMachine),
      ll_inv st -> GoFlatToRiscv.mcomp_sat (run1 iset) st ll_inv.
  Proof.
    intros st. unfold ll_inv.
    eapply runsToGood_is_Invariant with (jump := - 4) (pc_start := loop_pos)
                                        (pc_end := word.add loop_pos (word.of_Z 4)).
    - intro D.
      apply (f_equal word.unsigned) in D.
      rewrite word.unsigned_add in D.
      unshelve erewrite @word.unsigned_of_Z in D. 1: exact word_ok. (* PARAMRECORDS? *)
      unfold word.wrap in D.
      rewrite (Z.mod_small 4) in D; cycle 1. {
        simpl. pose proof four_fits. blia.
      }
      rewrite Z.mod_eq in D by apply pow2width_nonzero.
      let ww := lazymatch type of D with context [(2 ^ ?ww)] => ww end in set (w := ww) in *.
      progress replace w with (w - 2 + 2) in D at 3 by blia.
      rewrite Z.pow_add_r in D by (subst w; destruct width_cases as [E | E]; simpl in *; blia).
      change (2 ^ 2) with 4 in D.
      match type of D with
      | ?x = ?x + 4 - ?A * 4 * ?B => assert (A * B = 1) as C by blia
      end.
      apply Z.eq_mul_1 in C.
      destruct C as [C | C];
        subst w; destruct width_cases as [E | E]; simpl in *; rewrite E in C; cbv in C; discriminate C.
    - intros.
      unfold ll_good, machine_ok in *.
      simp.
      etransitivity. 1: eassumption.
      destruct done; solve_word_eq word_ok.
    - (* Show that ll_ready (almost) ignores pc, nextPc, and metrics *)
      intros.
      unfold ll_good, machine_ok in *.
      simp.
      destr_RiscvMachine state.
      repeat match goal with
             | |- exists _, _  => eexists
             | |- _ /\ _ => split
             | |- _ => progress cbv beta iota
             | |- _ => eassumption
             | |- _ => reflexivity
             end.
      + destruct mlOk. subst. simpl in *. subst loop_pos. solve_divisibleBy4.
      + solve_word_eq word_ok.
      + subst. case TODO_sam. (* show that backjump preserves valid_machine *)
    - unfold ll_good, machine_ok.
      intros. simp. assumption.
    - cbv. intuition discriminate.
    - solve_divisibleBy4.
    - solve_word_eq word_ok.
    - unfold ll_good, machine_ok.
      intros. simp. split.
      + eexists. case TODO_sam.
      + case TODO_sam. (* TODO the jump back Jal has to be in xframe *)
    - (* use compiler correctness for loop body *)
      intros.
      unfold ll_good in *. simp.
      match goal with
      | H: ProgramSatisfiesSpec _ _ _ _ |- _ => pose proof H as sat; destruct H
      end.
      unfold hl_inv in loop_body_correct.
      specialize loop_body_correct with (l := map.empty) (mc := bedrock2.MetricLogging.mkMetricLog 0 0 0 0).
      lazymatch goal with
      | H: context[@word.add ?w ?wo ?x (word.of_Z 0)] |- _ =>
        replace (@word.add w wo x (word.of_Z 0)) with x in H
      end.
      2: {
        (* PARAMRECORDS *)
        symmetry. unshelve eapply SimplWordExpr.add_0_r.
      }
      subst.
      match goal with
      | H: _ |- _ => pose proof H; apply compile_prog_to_compile in H;
                     destruct H as [ before [ finstrs [ ? ? ] ] ]
      end.
      subst.
      eapply runsTo_weaken.
      + pose proof compiler_correct as P. unfold runsTo in P.
        eapply P; clear P. 6: {
          eapply loop_body_correct; eauto.
        }
        all: try eassumption.
        eapply machine_ok_frame_instrs_app_l. eassumption.
      + cbv beta.
        intros. simp. do 3 eexists.
        ssplit; try eassumption.
        eexists.
        split; [eassumption|].
        split; [eassumption|].
        case TODO_sam. (* similar to machine_ok_frame_instrs_app_l *)
    Unshelve. all: case TODO_sam.
  Qed.

  Lemma ll_inv_implies_prefix_of_good: forall st,
      ll_inv st -> exists suff, spec.(goodTrace) (suff ++ st.(getLog)).
  Proof.
    unfold ll_inv, runsToGood_Invariant. intros. simp.
    eapply extend_runsTo_to_good_trace. 2: case TODO_sam. 2: eassumption.
    simpl. unfold ll_good, compile_inv, related, hl_inv,
           compose_relation, FlattenExprSimulation.related,
           RegRename.related, FlatToRiscvSimulation.related, FlatToRiscvFunctions.goodMachine.
    intros. simp. eassumption.
  Qed.

End Pipeline1.