Load loadpath.
Require Import veric.base.
Require Import Events.
Require Export veric.MemEvolve.

Lemma inject_separated_same_meminj: forall j m m', Events.inject_separated j j m m'.
  Proof. intros j m m' b; intros. congruence. Qed.

(* A "core semantics represents" a fairly traditional,
   sequential, small step semantics of computation.  They
   are designed to cooperate with "extensions"
   which give semantics to primtive constructs not defined
   by the extensible semantics (e.g., external function calls).

   The [G] type parameter is the type of global environments,
   the type [C] is the type of core states, and the type [E]
   is the type of extension requests.  The [at_external]
   function gives a way to determine when the sequential
   execution is blocked on an extension call, and to extract
   the data necessary to execute the call.  [after_external]
   give a way to inject the extension call results back into
   the sequential state so execution can continue.
   
  Lenb: the type parameter [D] stands for the type of initialization data, 
       eg list (ident * globvar V).

   [make_initial_core] produces the core state corresponding
   to an entry point of the program/module.  The arguments are the
   program's genv, a pointer to the function to run, and
   the arguments for that function.

   The [safely_halted] predicate indicates when a program state
   has reached a halted state, and what it's exit code/return value is
   when it has reached such a state.

   [corestep] is the fundamental small-step relation for
   the sequential semantics.

   The remaining properties give basic sanity properties which constrain
   the behavior of programs.
    1) a state cannot be both blocked on an extension call
        and also step,
    2) a state cannot both step and be halted
    3) a state cannot both be halted and blocked on an external call
 *)

Record CoreSemantics {G C M D:Type}: Type :=
  { initial_mem: G -> M -> D -> Prop;
    (*characterizes initial memories*)
  make_initial_core : G -> val -> list val -> option C;
  at_external : C -> option (external_function * signature * list val);
  after_external : option val -> C -> option C;
  safely_halted : C -> option val; 
  (*Lenb: return type used to be option int, so that only the exit code of eg main can be returned.
    As out envisioned linker will, however use safely_halted to detect that an external call has 
   finished execution, we need to allow arbitrary reutrn values*)

  corestep : G -> C -> M -> C -> M -> Prop;

  corestep_not_at_external: forall ge m q m' q', 
    corestep ge q m q' m' -> at_external q = None;

  corestep_not_halted: forall ge m q m' q', 
    corestep ge q m q' m' -> safely_halted q = None;

  at_external_halted_excl: forall q, 
    at_external q = None \/ safely_halted q = None;

   after_at_external_excl : forall retv q q',
    after_external retv q = Some q' -> at_external q' = None
  }.
Implicit Arguments CoreSemantics [].

(* Definition of multistepping. *)
Section corestepN.
  Context {G C M E D:Type} (Sem:CoreSemantics G C M D) (ge:G).

  Fixpoint corestepN (n:nat) : C -> M -> C -> M -> Prop :=
    match n with
    | O => fun c m c' m' => (c,m) = (c',m')
    | S k => fun c1 m1 c3 m3 => exists c2, exists m2,
               corestep Sem ge c1 m1 c2 m2 /\
               corestepN k c2 m2 c3 m3
    end.

  Lemma corestepN_add : forall n m c1 m1 c3 m3,
    corestepN (n+m) c1 m1 c3 m3 <->
    exists c2, exists m2,
      corestepN n c1 m1 c2 m2 /\
      corestepN m c2 m2 c3 m3.
  Proof.
    induction n; simpl; intuition.
    firstorder. firstorder.
    inv H. auto.
    decompose [ex and] H. clear H.
    destruct (IHn m x x0 c3 m3).
    apply H in H2. 
    decompose [ex and] H2. clear H2.
    repeat econstructor; eauto.
    decompose [ex and] H. clear H.
    exists x1. exists x2; split; auto.
    destruct (IHn m x1 x2 c3 m3). 
    eauto.
  Qed.

  Definition corestep_plus c m c' m' :=
    exists n, corestepN (S n) c m c' m'.

  Definition corestep_star c m c' m' :=
    exists n, corestepN n c m c' m'.

  Lemma corestep_plus_star : forall c1 c2 m1 m2,
       corestep_plus c1 m1 c2 m2 -> corestep_star c1 m1 c2 m2.
   Proof. intros. destruct H as [n1 H1]. eexists. apply H1. Qed.

  Lemma corestep_plus_trans : forall c1 c2 c3 m1 m2 m3,
       corestep_plus c1 m1 c2 m2 -> corestep_plus c2 m2 c3 m3 -> corestep_plus c1 m1 c3 m3.
   Proof. intros. destruct H as [n1 H1]. destruct H0 as [n2 H2].
        destruct (corestepN_add (S n1) (S n2) c1 m1 c3 m3) as [_ H].
        eexists. apply H. exists c2. exists m2. split; assumption.
   Qed.

  Lemma corestep_star_plus_trans : forall c1 c2 c3 m1 m2 m3,
       corestep_star c1 m1 c2 m2 -> corestep_plus c2 m2 c3 m3 -> corestep_plus c1 m1 c3 m3.
   Proof. intros. destruct H as [n1 H1]. destruct H0 as [n2 H2].
        destruct (corestepN_add n1 (S n2) c1 m1 c3 m3) as [_ H]. rewrite <- plus_n_Sm in H.
        eexists. apply H.  exists c2. exists m2.  split; assumption.
   Qed.

  Lemma corestep_plus_star_trans: forall c1 c2 c3 m1 m2 m3,
         corestep_plus c1 m1 c2 m2 -> corestep_star c2 m2 c3 m3 -> corestep_plus c1 m1 c3 m3.
   Proof. intros. destruct H as [n1 H1]. destruct H0 as [n2 H2].
        destruct (corestepN_add (S n1) n2 c1 m1 c3 m3) as [_ H]. rewrite plus_Sn_m in H.
        eexists. apply H.  exists c2. exists m2.  split; assumption.
   Qed.

   Lemma corestep_star_trans: forall c1 c2 c3 m1 m2 m3, 
        corestep_star c1 m1 c2 m2 -> corestep_star c2 m2 c3 m3 -> corestep_star c1 m1 c3 m3.
   Proof. intros. destruct H as [n1 H1]. destruct H0 as [n2 H2].
        destruct (corestepN_add n1 n2 c1 m1 c3 m3) as [_ H]. 
        eexists. apply H.  exists c2. exists m2.  split; assumption.
   Qed.

   Lemma corestep_plus_one: forall c m c' m',
       corestep  Sem ge c m c' m' -> corestep_plus c m c' m'.
     Proof. intros. unfold corestep_plus, corestepN. simpl.
          exists O. exists c'. exists m'. eauto. 
     Qed.

   Lemma corestep_plus_two: forall c m c' m' c'' m'',
       corestep  Sem ge c m c' m' -> corestep  Sem ge c' m' c'' m'' -> corestep_plus c m c'' m''.
     Proof. intros. 
          exists (S O). exists c'. exists m'. split; trivial. 
          exists c''. exists m''. split; trivial. reflexivity.
     Qed.

   Lemma corestep_star_zero: forall c m, corestep_star  c m c m.
     Proof. intros. exists O. reflexivity.  
     Qed.

   Lemma corestep_star_one: forall c m c' m',
       corestep  Sem ge c m c' m' -> corestep_star c m c' m'.
     Proof. intros. 
          exists (S O). exists c'. exists m'. split; trivial. reflexivity. 
     Qed.

   Lemma corestep_plus_split: forall c m c' m',
       corestep_plus c m c' m' ->
       exists c'', exists m'', corestep  Sem ge c m c'' m'' /\ corestep_star c'' m'' c' m'.
     Proof. intros.
         destruct H as [n [c2 [m2 [Hstep Hstar]]]]. simpl in*. 
         exists c2. exists m2. split. assumption. exists n. assumption.  
     Qed.

End corestepN.

Record CoopCoreSem {G C D} :=
{ coopsem :> CoreSemantics G C mem D;
  corestep_fwd : forall g c m c' m' (CS: corestep coopsem g c m c' m'), mem_forward m m';
  corestep_wdmem: forall g c m c' m' (CS: corestep coopsem g c m c' m'), 
           mem_wd m -> mem_wd m';
  initmem_wd: forall g m d, initial_mem coopsem g m d -> mem_wd m
}.
Implicit Arguments CoopCoreSem [ ].

Lemma inject_separated_incr_fwd: forall j j' m1 m2 j'' m2'
                        (InjSep : inject_separated j j' m1 m2)
                        (InjSep' : inject_separated j' j'' m1 m2')
                        (InjIncr' : inject_incr j' j'')
                       (Fwd: mem_forward m2 m2'),
               inject_separated j j'' m1 m2.
Proof.
intros. intros b. intros. remember (j' b) as z. 
destruct z; apply eq_sym in Heqz.
        destruct p. specialize (InjIncr' _ _ _ Heqz). rewrite InjIncr' in H0. inv H0.
        apply (InjSep _ _ _ H Heqz). 
destruct (InjSep' _ _ _ Heqz H0).
    split. trivial.
    intros N. apply H2. eapply Fwd. apply N.
Qed.

Lemma external_call_mem_forward:
  forall (ef : external_function) (F V : Type) (ge : Genv.t F V)
    (vargs : list val) (m1 : mem) (t : trace) (vres : val) (m2 : mem),
  external_call ef ge vargs m1 t vres m2 -> mem_forward m1 m2.
  Proof.
    intros.
    intros b Hb.
    split; intros. eapply external_call_valid_block; eauto.
      eapply external_call_max_perm; eauto.
  Qed.

(*
 This predicate restricts what coresteps are allowed
   to do.  Essentially, a corestep can only store, allocacte
   and free, and must do so respecting permissions.*) 
Definition allowed_core_modification (m1 m2:mem) :=
  mem_forward m1 m2 /\
  (forall b ofs p,
    Mem.perm m1 b ofs Cur p ->
    (Mem.perm m2 b ofs Cur p) \/
    (Mem.perm m1 b ofs Cur Freeable /\ forall p', ~Mem.perm m2 b ofs Cur p')) /\
  (forall b ofs p,
    Mem.valid_block m1 b ->
    Mem.perm m2 b ofs Cur p ->
    Mem.perm m1 b ofs Cur p) /\
  (forall b ofs' n vs,
    Mem.loadbytes m1 b ofs' n = Some vs ->
      (Mem.loadbytes m2 b ofs' n = Some vs) \/
      (exists ofs, ofs' <= ofs < ofs' + n /\ Mem.perm m1 b ofs Cur Writable)).

(* The kinds of extensible semantics used by CompCert.  Memories are
   CompCert memories and external requests must contain external functions.
 *)
Record CompcertCoreSem {G C D} :=
{ csem :> CoreSemantics G C mem D
; csem_corestep_fun: forall ge m q m1 q1 m2 q2, 
       corestep csem ge q m q1 m1 ->
       corestep csem ge q m q2 m2 -> 
          (q1, m1) = (q2, m2)

; csem_allowed_modifications :
    forall ge c m c' m',
      corestep csem ge c m c' m' ->
      allowed_core_modification m m'
}.
Implicit Arguments CompcertCoreSem [ ].

(*
Lemma corestepN_fun (G C D:Type) (CSem:CompcertCoreSem G C D) :
  forall ge n c m c1 m1 c2 m2,
    corestepN CSem ge n c m c1 m1 ->
    corestepN CSem ge n c m c2 m2 ->
    (c1,m1) = (c2,m2).
Proof.
  induction n; simpl; intuition (try congruence).
  decompose [ex and] H. clear H.
  decompose [ex and] H0. clear H0.
  assert ((x,x0) = (x1,x2)).
  eapply csem_corestep_fun; eauto.
  inv H0.
  eapply IHn; eauto.
Qed.
*)

Inductive entry_points_compose: 
  list (val*val*signature) -> list (val*val*signature) -> 
  list (val*val*signature) -> Prop :=
| EPC1: forall v1 v2 v3 sig r1 r2 r3, 
  entry_points_compose r1 r2 r3 ->
  entry_points_compose ((v1,v2,sig)::r1) ((v2,v3,sig)::r2) ((v1,v3,sig)::r3)
| EPC0: entry_points_compose nil nil nil.

(* Here we present a module type which expresses the sort of forward simulation
   lemmas we have avalaible.  The idea is that these lemmas would be used in
   the individual compiler passes and the composition lemma would be used
   to build the main lemma.
 *)

(*
Module Type SIMULATIONS.
*)
Lemma allowed_core_modification_refl : forall m,
  allowed_core_modification m m.
Proof. unfold allowed_core_modification. intros.
  split; intros. apply mem_forward_refl.
  split; intros. eauto.
  split; intros; eauto.
Qed.

Lemma allowed_core_modification_trans : forall m1 m2 m3,
  allowed_core_modification m1 m2 ->
  allowed_core_modification m2 m3 ->
  allowed_core_modification m1 m3.
Proof. intros m1 m2 m3 [X1 [X2 [X3 X4]] [Y1 [Y2 [Y3 Y4]]]].
  split; intros.
     eapply mem_forward_trans; eauto.
  split; intros. 
    destruct (X2 _ _ _ H).
        destruct (Y2 _ _ _ H0). left; assumption.
        destruct H1. right.
           split. eapply X3. eapply Mem.perm_valid_block; eauto. assumption.
           assumption.
     destruct H0. right.
       split. assumption.
       intros. intros N. eapply H1. eapply Y3. apply X1. eapply  Mem.perm_valid_block; eauto. apply N.
  split; intros.
     eapply X3. apply H. eapply Y3. apply X1. apply H. apply H0.
   destruct (X4 _ _  _ _ H).
      destruct (Y4 _ _ _ _ H0). left; assumption.
         destruct H1 as [ofs1 [HH KK]].
         apply X3 in KK. right. exists ofs1. split; assumption.
      apply Mem.loadbytes_range_perm in H. apply H in HH. eapply  Mem.perm_valid_block; eauto.
  right. assumption.
Qed.

Lemma free_allowed_core_mod : forall m1 b lo hi m2,
  Mem.free m1 b lo hi = Some m2 ->
  allowed_core_modification m1 m2.
Proof. unfold allowed_core_modification. intros.
  split. intros bb; intros.
      split. eapply Mem.valid_block_free_1; eauto.
      intros. eapply Mem.perm_free_3; eauto.
  split; intros.
      destruct (Mem.perm_free_inv _ _ _ _ _ H _ _ _ _ H0) as [[? ?] | ?]; subst.
         right. split; intros. 
                     apply Mem.free_range_perm in H. apply H. assumption.
                     eapply Mem.perm_free_2; eauto.
     left; assumption.
  split; intros.
       eapply Mem.perm_free_3; eauto.
       assert (A1:= Mem.loadbytes_length _ _ _ _ _ H0).
       assert (ZZ:= Mem.loadbytes_range_perm _ _ _ _ _ H0). unfold Mem.range_perm in ZZ. 
       assert (Q1:= Mem.perm_free_inv _ _ _ _ _ H).
admit. (*what about the case where n=0 ie vs=nil?*)
Qed.

Lemma alloc_allowed_core_mod : forall m1 lo hi m2 b,
  Mem.alloc m1 lo hi = (m2,b) ->
  allowed_core_modification m1 m2.
Proof. intros.
   split. intros bb. intros.
      split. eapply Mem.valid_block_alloc; eauto.
      intros. assert (Z1:= Mem.perm_alloc_inv _ _ _ _ _ H _ _ _ _ H1).
          destruct (zeq bb b); subst. apply (Mem.fresh_block_alloc _ _ _ _ _ H) in H0. contradiction.
          assumption.
  split; intros.
    left. eapply Mem.perm_alloc_1; eauto.
  split; intros.
      assert (Z1:= Mem.perm_alloc_inv _ _ _ _ _ H _ _ _ _ H1).
      destruct (zeq b0 b); subst. apply (Mem.fresh_block_alloc _ _ _ _ _ H) in H0. contradiction.
          assumption.
  admit. (*To be completed...*)
Qed.
      
Lemma store_allowed_core_mod : forall m1 chunk v b ofs m2,
  Mem.store chunk m1 b ofs v = Some m2 ->
  allowed_core_modification m1 m2.
Proof. intros.
   split. intros bb. intros.
      split. eapply Mem.store_valid_block_1; eauto.
      intros. eapply Mem.perm_store_2; eauto. 
  split; intros. 
    left. eapply Mem.perm_store_1; eauto. 
  split; intros.
     eapply Mem.perm_store_2; eauto. 
  admit. (*To be completed...*)
Qed.

Hint Resolve 
  allowed_core_modification_refl
  allowed_core_modification_trans
  free_allowed_core_mod
  alloc_allowed_core_mod
  store_allowed_core_mod : allowed_mod.

(* First a forward simulation for passes which do not alter the memory
     layout at all. *)
Module Sim_eq.
Section Forward_simulation_equals. 
  Context {M G1 C1 D1 G2 C2 D2:Type}
          {Sem1 : CoreSemantics G1 C1 M D1}
          {Sem2 : CoreSemantics G2 C2 M D2}

          {ge1:G1}
          {ge2:G2}
          {entry_points : list (val * val * signature)}.

  Record Forward_simulation_equals :=
  { core_data:Type;

    match_core : core_data -> C1 -> C2 -> Prop;
    core_ord : core_data -> core_data -> Prop;
    core_ord_wf : well_founded core_ord;

    core_diagram : 
      forall st1 m st1' m', corestep Sem1 ge1 st1 m st1' m' ->
      forall d st2, match_core d st1 st2 ->
        exists st2', exists d',
          match_core d' st1' st2' /\
          ((corestep_plus Sem2 ge2 st2 m st2' m') \/
            corestep_star Sem2 ge2 st2 m st2' m' /\
            core_ord d' d);

   (*LENB: Maybe this should be reformulated so that
      make_initial_core Sem1 ge1 v1 vals = Some c1 implies
       existence of some c2 with 
          make_initial_core Sem2 ge2 v2 vals = Some c2 /\  match_core cd c1 c2?*)
    core_initial : forall v1 v2 sig,
      In (v1,v2,sig) entry_points ->
        forall vals,
          Forall2 (Val.has_type) vals (sig_args sig) ->
          exists cd, exists c1, exists c2,
            make_initial_core Sem1 ge1 v1 vals = Some c1 /\
            make_initial_core Sem2 ge2 v2 vals = Some c2 /\
            match_core cd c1 c2;

    core_halted : forall cd c1 c2 v,
      match_core cd c1 c2 ->
      safely_halted Sem1 c1 = Some v ->
      safely_halted Sem2 c2 = Some v;

    core_at_external : 
      forall d st1 st2 e args ef_sig,
        match_core d st1 st2 ->
        at_external Sem1 st1 = Some (e,ef_sig,args) ->
        ( at_external Sem2 st2 = Some (e,ef_sig,args) /\
          Forall2 Val.has_type args (sig_args ef_sig) );

    core_after_external :
      forall d st1 st2 ret e args ef_sig,
        match_core d st1 st2 ->
        at_external Sem1 st1 = Some (e,ef_sig,args) ->
        at_external Sem2 st2 = Some (e,ef_sig,args) ->
        Forall2 Val.has_type args (sig_args ef_sig) ->
        Val.has_type ret (proj_sig_res ef_sig) ->
        exists st1', exists st2', exists d',
          after_external Sem1 (Some ret) st1 = Some st1' /\
          after_external Sem2 (Some ret) st2 = Some st2' /\
          match_core d' st1' st2'
  }.
End Forward_simulation_equals. 

Implicit Arguments Forward_simulation_equals [[G1] [C1] [G2] [C2]].
End Sim_eq.

Module Sim_ext.
(* Next, an axiom for passes that allow the memory to undergo extension. *)
Section Forward_simulation_extends. 
  Context {G1 C1 D1 G2 C2 D2:Type}
          {Sem1 : CoreSemantics G1 C1 mem D1}
          {Sem2 : CoreSemantics  G2 C2 mem D2}

          {ge1:G1}
          {ge2:G2}
          {entry_points : list (val * val * signature)}.

  Record Forward_simulation_extends := {
    core_data : Type;

    match_state : core_data -> C1 -> mem -> C2 -> mem -> Prop;
    core_ord : core_data -> core_data -> Prop;
    core_ord_wf : well_founded core_ord;

    core_diagram : 
      forall st1 m1 st1' m1', corestep Sem1 ge1 st1 m1 st1' m1' ->
      forall cd st2 m2,
        match_state cd st1 m1 st2 m2 ->
        exists st2', exists m2', exists cd',
          match_state cd' st1' m1' st2' m2' /\
          ((corestep_plus Sem2 ge2 st2 m2 st2' m2') \/
            corestep_star Sem2 ge2 st2 m2 st2' m2' /\
            core_ord cd' cd);

    core_initial : forall v1 v2 sig,
      In (v1,v2,sig) entry_points ->
        forall vals vals' m1 m2,
          Forall2 Val.lessdef vals vals' ->
          Forall2 (Val.has_type) vals' (sig_args sig) ->
          Mem.extends m1 m2 ->
          exists cd, exists c1, exists c2,
            make_initial_core Sem1 ge1 v1 vals = Some c1 /\
            make_initial_core Sem2 ge2 v2 vals' = Some c2 /\
            match_state cd c1 m1 c2 m2;

    core_halted : 
      forall cd st1 m1 st2 m2 v1,
        match_state cd st1 m1 st2 m2 ->
        safely_halted Sem1 st1 = Some v1 ->
        exists v2, Val.lessdef v1 v2 /\
            safely_halted Sem2 st2 = Some v2 /\
            Mem.extends m1 m2;

    core_at_external : 
      forall cd st1 m1 st2 m2 e vals1 ef_sig,
        match_state cd st1 m1 st2 m2 ->
        at_external Sem1 st1 = Some (e,ef_sig,vals1) ->
        exists vals2,
          Mem.extends m1 m2 /\
          Forall2 Val.lessdef vals1 vals2 /\
          Forall2 (Val.has_type) vals2 (sig_args ef_sig) /\
          at_external Sem2 st2 = Some (e,ef_sig,vals2);

    core_after_external :
      forall cd st1 st2 m1 m2 e vals1 vals2 ret1 ret2 m1' m2' ef_sig,
        match_state cd st1 m1 st2 m2 ->
        at_external Sem1 st1 = Some (e,ef_sig,vals1) ->
        at_external Sem2 st2 = Some (e,ef_sig,vals2) ->

        Forall2 Val.lessdef vals1 vals2 ->
        Forall2 (Val.has_type) vals2 (sig_args ef_sig) ->
        mem_forward m1 m1' ->
        mem_forward m2 m2' ->

        mem_unchanged_on (loc_out_of_bounds m1) m2 m2' -> (*ie spill-locations didn't change*)
        Val.lessdef ret1 ret2 ->
        Mem.extends m1' m2' ->

        Val.has_type ret2 (proj_sig_res ef_sig) -> 

        exists st1', exists st2', exists cd',
          after_external Sem1 (Some ret1) st1 = Some st1' /\
          after_external Sem2 (Some ret2) st2 = Some st2' /\
          match_state cd' st1' m1' st2' m2'
   }.
End Forward_simulation_extends.

Implicit Arguments Forward_simulation_extends [[G1] [C1] [G2] [C2]].
End Sim_ext.

Module CoopSim_ext.
(* Next, an axiom for passes that allow the memory to undergo extension. *)
Section Forward_simulation_extends. 
  Context {G1 C1 D1 G2 C2 D2:Type}
          {Sem1 : CoopCoreSem G1 C1 D1}
          {Sem2 : CoopCoreSem  G2 C2 D2}

          {ge1:G1}
          {ge2:G2}
          {entry_points : list (val * val * signature)}.

  Record Forward_simulation_extends := {
    core_data : Type;

    match_state : core_data -> C1 -> mem -> C2 -> mem -> Prop;
    core_ord : core_data -> core_data -> Prop;
    core_ord_wf : well_founded core_ord;

    (*Matching memories should be well-defined ie not contain values
        with invalid/"dangling" block numbers*)
    match_memwd: forall d c1 m1 c2 m2,  match_state d c1 m1 c2 m2 -> 
               (mem_wd m1 /\ mem_wd m2);

    (*The following axiom could be strengthened to extends m1 m2*)
    match_validblocks: forall d c1 m1 c2 m2,  match_state d c1 m1 c2 m2 -> 
          forall b, Mem.valid_block m1 b <-> Mem.valid_block m2 b;

    core_diagram : 
      forall st1 m1 st1' m1', corestep Sem1 ge1 st1 m1 st1' m1' ->
      forall cd st2 m2,
        match_state cd st1 m1 st2 m2 ->
        exists st2', exists m2', exists cd',
          match_state cd' st1' m1' st2' m2' /\
          ((corestep_plus Sem2 ge2 st2 m2 st2' m2') \/
            corestep_star Sem2 ge2 st2 m2 st2' m2' /\
            core_ord cd' cd);

    core_initial : forall v1 v2 sig,
      In (v1,v2,sig) entry_points ->
        forall vals vals' m1 m2,
          Forall2 Val.lessdef vals vals' ->
          Forall2 (Val.has_type) vals' (sig_args sig) ->
          Mem.extends m1 m2 ->
          mem_wd m1 -> mem_wd m2 ->
          exists cd, exists c1, exists c2,
            make_initial_core Sem1 ge1 v1 vals = Some c1 /\
            make_initial_core Sem2 ge2 v2 vals' = Some c2 /\
            match_state cd c1 m1 c2 m2;

    core_halted : 
      forall cd st1 m1 st2 m2 v1,
        match_state cd st1 m1 st2 m2 ->
        safely_halted Sem1 st1 = Some v1 -> val_valid v1 m1 ->
        exists v2, Val.lessdef v1 v2 /\
            safely_halted Sem2 st2 = Some v2 /\
            Mem.extends m1 m2 /\ val_valid v2 m2;

    core_at_external : 
      forall cd st1 m1 st2 m2 e vals1 ef_sig,
        match_state cd st1 m1 st2 m2 ->
        at_external Sem1 st1 = Some (e,ef_sig,vals1) ->
        (forall v1, In v1 vals1 -> val_valid v1 m1) -> 
        exists vals2,
          Mem.extends m1 m2 /\
          Forall2 Val.lessdef vals1 vals2 /\
          Forall2 (Val.has_type) vals2 (sig_args ef_sig) /\
          at_external Sem2 st2 = Some (e,ef_sig,vals2) /\
          (forall v2, In v2 vals2 -> val_valid v2 m2);

    core_after_external :
      forall cd st1 st2 m1 m2 e vals1 vals2 ret1 ret2 m1' m2' ef_sig,
        match_state cd st1 m1 st2 m2 ->
        at_external Sem1 st1 = Some (e,ef_sig,vals1) ->
        (forall v1, In v1 vals1 -> val_valid v1 m1) -> 
        at_external Sem2 st2 = Some (e,ef_sig,vals2) ->

        Forall2 Val.lessdef vals1 vals2 ->
        Forall2 (Val.has_type) vals2 (sig_args ef_sig) ->
        mem_forward m1 m1' ->
        mem_forward m2 m2' ->

        mem_unchanged_on (loc_out_of_bounds m1) m2 m2' -> (*ie spill-locations didn't change*)
        Val.lessdef ret1 ret2 ->
        Mem.extends m1' m2' ->

        Val.has_type ret2 (proj_sig_res ef_sig) -> 

        mem_wd m1' -> mem_wd m2' -> val_valid ret1 m1' -> val_valid ret2 m2' ->

        exists st1', exists st2', exists cd',
          after_external Sem1 (Some ret1) st1 = Some st1' /\
          after_external Sem2 (Some ret2) st2 = Some st2' /\
          match_state cd' st1' m1' st2' m2'
   }.
End Forward_simulation_extends.

Implicit Arguments Forward_simulation_extends [[G1] [C1] [G2] [C2]].
End CoopSim_ext.

(* An axiom for passes that use memory injections. *)
Module Sim_inj.
Section Forward_simulation_inject. 
  Context {F1 V1 C1 D1 G2 C2 D2:Type}
          {Sem1 : CoreSemantics (Genv.t F1 V1) C1 mem D1}
          {Sem2 : CoreSemantics G2 C2 mem D2}
          {ge1: Genv.t F1 V1}
          {ge2:G2}
          {entry_points : list (val * val * signature)}.

Record Forward_simulation_inject := {
    core_data : Type;
    match_state : core_data -> meminj -> C1 -> mem -> C2 -> mem -> Prop;
    core_ord : core_data -> core_data -> Prop;
    core_ord_wf : well_founded core_ord;
    core_diagram : 
      forall st1 m1 st1' m1', corestep Sem1 ge1 st1 m1 st1' m1' ->
      forall cd st2 j m2,
        match_state cd j st1 m1 st2 m2 ->
        exists st2', exists m2', exists cd', exists j',
          inject_incr j j' /\
          inject_separated j j' m1 m2 /\
          match_state cd' j' st1' m1' st2' m2' /\
          mem_unchanged_on (loc_unmapped j) m1 m1' /\
          mem_unchanged_on (loc_out_of_reach j m1) m2 m2' /\
          ((corestep_plus Sem2 ge2 st2 m2 st2' m2') \/
            corestep_star Sem2 ge2 st2 m2 st2' m2' /\
            core_ord cd' cd);

    core_initial : forall v1 v2 sig,
       In (v1,v2,sig) entry_points -> 
       forall vals1 c1 m1 j vals2 m2,
          make_initial_core Sem1 ge1 v1 vals1 = Some c1 ->
          Mem.inject j m1 m2 -> 
          (*Is this line needed?? (forall w1 w2 sigg,  In (w1,w2,sigg) entry_points -> val_inject j w1 w2) ->*)
           Forall2 (val_inject j) vals1 vals2 ->

          Forall2 (Val.has_type) vals2 (sig_args sig) ->
          exists cd, exists c2, 
            make_initial_core Sem2 ge2 v2 vals2 = Some c2 /\
            match_state cd j c1 m1 c2 m2;

    core_halted : forall cd j c1 m1 c2 m2 v1,
      match_state cd j c1 m1 c2 m2 ->
      safely_halted Sem1 c1 = Some v1 ->
     exists v2, val_inject j v1 v2 /\
          safely_halted Sem2 c2 = Some v2 /\
          Mem.inject j m1 m2;

    core_at_external : 
      forall cd j st1 m1 st2 m2 e vals1 ef_sig,
        match_state cd j st1 m1 st2 m2 ->
        at_external Sem1 st1 = Some (e,ef_sig,vals1) ->
        ( Mem.inject j m1 m2 /\
          meminj_preserves_globals ge1 j /\ (*LENB: also added meminj_preserves_global HERE*)
          exists vals2, Forall2 (val_inject j) vals1 vals2 /\
          Forall2 (Val.has_type) vals2 (sig_args ef_sig) /\
          at_external Sem2 st2 = Some (e,ef_sig,vals2));

    core_after_external :
      forall cd j j' st1 st2 m1 e vals1 (*vals2*) ret1 m1' m2 m2' ret2 ef_sig,
        Mem.inject j m1 m2->
        match_state cd j st1 m1 st2 m2 ->
        at_external Sem1 st1 = Some (e,ef_sig,vals1) ->
(*     at_external Sem2 st2 = Some (e,ef_sig,vals2) ->
        Forall2 (val_inject j) vals1 vals2 ->*)

(* LENB: I added meminj_preserves_globals ge1 j as another asumption here,
      in order to get rid of the unprovable Lemma meminj_preserved_globals_inject_incr stated below. 
     The introduction of meminj_preserves_globals ge1 required specializing G1 to (Genv.t F1 V1).
      In principle, we could also specialize G2 to (Genv.t F1 V1).*)
        meminj_preserves_globals ge1 j -> 

        inject_incr j j' ->
        inject_separated j j' m1 m2 ->
        Mem.inject j' m1' m2' ->
        val_inject j' ret1 ret2 ->

         mem_forward m1 m1'  -> 
         mem_unchanged_on (loc_unmapped j) m1 m1' ->
         mem_forward m2 m2' -> 
         mem_unchanged_on (loc_out_of_reach j m1) m2 m2' ->
         Val.has_type ret2 (proj_sig_res ef_sig) -> 

        exists cd', exists st1', exists st2',
          after_external Sem1 (Some ret1) st1 = Some st1' /\
          after_external Sem2 (Some ret2) st2 = Some st2' /\
          match_state cd' j' st1' m1' st2' m2'
    }.

End Forward_simulation_inject. 

(*Implicit Arguments Forward_simulation_inject [[G1] [C1] [G2] [C2]].*)
Implicit Arguments Forward_simulation_inject [[F1][V1] [C1] [G2] [C2]].
End Sim_inj.

Module CoopSim_inj.
Section Forward_simulation_inject. 
  Context {F1 V1 C1 D1 G2 C2 D2:Type}
          {Sem1 : CoreSemantics (Genv.t F1 V1) C1 mem D1}
          {Sem2 : CoreSemantics G2 C2 mem D2}
          {ge1: Genv.t F1 V1}
          {ge2:G2}
          {entry_points : list (val * val * signature)}.

Record Forward_simulation_inject := {
    core_data : Type;
    match_state : core_data -> meminj -> C1 -> mem -> C2 -> mem -> Prop;
    core_ord : core_data -> core_data -> Prop;
    core_ord_wf : well_founded core_ord;

    (*Matching memories should be well-defined ie not contain values
        with invalid/"dangling" block numbers*)
    match_memwd: forall d j c1 m1 c2 m2,  match_state d j c1 m1 c2 m2 -> 
               (mem_wd m1 /\ mem_wd m2);

    (*The following axiom could be strengthened to inject j m1 m2*)
    match_validblocks: forall d j c1 m1 c2 m2,  match_state d j c1 m1 c2 m2 -> 
          forall b1 b2 ofs, j b1 = Some(b2,ofs) -> 
               (Mem.valid_block m1 b1 /\ Mem.valid_block m2 b2);

    core_diagram : 
      forall st1 m1 st1' m1', corestep Sem1 ge1 st1 m1 st1' m1' ->
      forall cd st2 j m2,
        match_state cd j st1 m1 st2 m2 ->
        exists st2', exists m2', exists cd', exists j',
          inject_incr j j' /\
          inject_separated j j' m1 m2 /\
          match_state cd' j' st1' m1' st2' m2' /\
          ((corestep_plus Sem2 ge2 st2 m2 st2' m2') \/
            corestep_star Sem2 ge2 st2 m2 st2' m2' /\
            core_ord cd' cd);

    core_initial : forall v1 v2 sig,
       In (v1,v2,sig) entry_points -> 
       forall vals1 c1 m1 j vals2 m2,
          make_initial_core Sem1 ge1 v1 vals1 = Some c1 ->
          Mem.inject j m1 m2 -> 
          mem_wd m1 -> mem_wd m2 ->
          (*Is this line needed?? (forall w1 w2 sigg,  In (w1,w2,sigg) entry_points -> val_inject j w1 w2) ->*)
           Forall2 (val_inject j) vals1 vals2 ->

          Forall2 (Val.has_type) vals2 (sig_args sig) ->
          exists cd, exists c2, 
            make_initial_core Sem2 ge2 v2 vals2 = Some c2 /\
            match_state cd j c1 m1 c2 m2;

    core_halted : forall cd j c1 m1 c2 m2 v1,
      match_state cd j c1 m1 c2 m2 ->
      safely_halted Sem1 c1 = Some v1 ->
      val_valid v1 m1 ->
     exists v2, val_inject j v1 v2 /\
          safely_halted Sem2 c2 = Some v2 /\
          Mem.inject j m1 m2 /\ val_valid v2 m2;

    core_at_external : 
      forall cd j st1 m1 st2 m2 e vals1 ef_sig,
        match_state cd j st1 m1 st2 m2 ->
        at_external Sem1 st1 = Some (e,ef_sig,vals1) ->
        (forall v1, In v1 vals1 -> val_valid v1 m1) ->
        ( Mem.inject j m1 m2 /\
          meminj_preserves_globals ge1 j /\ (*LENB: also added meminj_preserves_global HERE*)
          exists vals2, Forall2 (val_inject j) vals1 vals2 /\
          Forall2 (Val.has_type) vals2 (sig_args ef_sig) /\
          at_external Sem2 st2 = Some (e,ef_sig,vals2) /\
          (forall v2, In v2 vals2 -> val_valid v2 m2));

    core_after_external :
      forall cd j j' st1 st2 m1 e vals1 (*vals2*) ret1 m1' m2 m2' ret2 ef_sig,
        Mem.inject j m1 m2->
        match_state cd j st1 m1 st2 m2 ->
        at_external Sem1 st1 = Some (e,ef_sig,vals1) ->
        (forall v1, In v1 vals1 -> val_valid v1 m1) ->
(*     at_external Sem2 st2 = Some (e,ef_sig,vals2) ->
        Forall2 (val_inject j) vals1 vals2 ->*)

(* LENB: I added meminj_preserves_globals ge1 j as another asumption here,
      in order to get rid of the unprovable Lemma meminj_preserved_globals_inject_incr stated below. 
     The introduction of meminj_preserves_globals ge1 required specializing G1 to (Genv.t F1 V1).
      In principle, we could also specialize G2 to (Genv.t F1 V1).*)
        meminj_preserves_globals ge1 j -> 

        inject_incr j j' ->
        inject_separated j j' m1 m2 ->
        Mem.inject j' m1' m2' ->
        val_inject j' ret1 ret2 ->

         mem_forward m1 m1'  -> 
         mem_unchanged_on (loc_unmapped j) m1 m1' ->
         mem_forward m2 m2' -> 
         mem_unchanged_on (loc_out_of_reach j m1) m2 m2' ->
         Val.has_type ret2 (proj_sig_res ef_sig) -> 

        mem_wd m1' -> mem_wd m2' -> val_valid ret1 m1' -> val_valid ret2 m2' ->

        exists cd', exists st1', exists st2',
          after_external Sem1 (Some ret1) st1 = Some st1' /\
          after_external Sem2 (Some ret2) st2 = Some st2' /\
          match_state cd' j' st1' m1' st2' m2'
    }.

End Forward_simulation_inject. 

(*Implicit Arguments Forward_simulation_inject [[G1] [C1] [G2] [C2]].*)
Implicit Arguments Forward_simulation_inject [[F1][V1] [C1] [G2] [C2]].
End CoopSim_inj.

(* An axiom for passes that use memory injections 
   -- exposes core_data and match_state *)
Module Sim_inj_exposed.
Section Forward_simulation_inject. 
  Context {F1 V1 C1 D1 G2 C2 D2:Type}
          {Sem1 : CoreSemantics (Genv.t F1 V1) C1 mem D1}
          {Sem2 : CoreSemantics G2 C2 mem D2}

          {ge1: Genv.t F1 V1}
          {ge2:G2}
          {entry_points : list (val * val * signature)}
          {core_data : Type}
          {match_state : core_data -> meminj -> C1 -> mem -> C2 -> mem -> Prop}
          {core_ord : core_data -> core_data -> Prop}.

Record Forward_simulation_inject := {
    core_ord_wf : well_founded core_ord;
    core_diagram : 
      forall st1 m1 st1' m1', corestep Sem1 ge1 st1 m1 st1' m1' ->
      forall cd st2 j m2,
        match_state cd j st1 m1 st2 m2 ->
        exists st2', exists m2', exists cd', exists j',
          inject_incr j j' /\
          inject_separated j j' m1 m2 /\
          match_state cd' j' st1' m1' st2' m2' /\
          mem_unchanged_on (loc_unmapped j) m1 m1' /\
          mem_unchanged_on (loc_out_of_reach j m1) m2 m2' /\
          ((corestep_plus Sem2 ge2 st2 m2 st2' m2') \/
            corestep_star Sem2 ge2 st2 m2 st2' m2' /\
            core_ord cd' cd);

    core_initial : forall v1 v2 sig,
       In (v1,v2,sig) entry_points -> 
       forall vals1 c1 m1 j vals2 m2,
          make_initial_core Sem1 ge1 v1 vals1 = Some c1 ->
          Mem.inject j m1 m2 -> 
           Forall2 (val_inject j) vals1 vals2 ->
          Forall2 (Val.has_type) vals2 (sig_args sig) ->
          exists cd, exists c2, 
            make_initial_core Sem2 ge2 v2 vals2 = Some c2 /\
            match_state cd j c1 m1 c2 m2;

    core_halted : forall cd j c1 m1 c2 m2 v1,
      match_state cd j c1 m1 c2 m2 ->
      safely_halted Sem1 c1 = Some v1 ->
     exists v2, val_inject j v1 v2 /\
          safely_halted Sem2 c2 = Some v2 /\
          Mem.inject j m1 m2;

    core_at_external : 
      forall cd j st1 m1 st2 m2 e vals1 ef_sig,
        match_state cd j st1 m1 st2 m2 ->
        at_external Sem1 st1 = Some (e,ef_sig,vals1) ->
        ( Mem.inject j m1 m2 /\
          meminj_preserves_globals ge1 j /\ 
          exists vals2, Forall2 (val_inject j) vals1 vals2 /\
          Forall2 (Val.has_type) vals2 (sig_args ef_sig) /\
          at_external Sem2 st2 = Some (e,ef_sig,vals2));

    core_after_external :
      forall cd j j' st1 st2 m1 e vals1 ret1 m1' m2 m2' ret2 ef_sig,
        Mem.inject j m1 m2->
        match_state cd j st1 m1 st2 m2 ->
        at_external Sem1 st1 = Some (e,ef_sig,vals1) ->
        meminj_preserves_globals ge1 j -> 

        inject_incr j j' ->
        inject_separated j j' m1 m2 ->
        Mem.inject j' m1' m2' ->
        val_inject j' ret1 ret2 ->

         mem_forward m1 m1'  -> 
         mem_unchanged_on (loc_unmapped j) m1 m1' ->
         mem_forward m2 m2' -> 
         mem_unchanged_on (loc_out_of_reach j m1) m2 m2' ->
         Val.has_type ret2 (proj_sig_res ef_sig) -> 

        exists cd', exists st1', exists st2',
          after_external Sem1 (Some ret1) st1 = Some st1' /\
          after_external Sem2 (Some ret2) st2 = Some st2' /\
          match_state cd' j' st1' m1' st2' m2'
    }.

End Forward_simulation_inject. 

Implicit Arguments Forward_simulation_inject [[F1][V1] [C1] [G2] [C2]].
End Sim_inj_exposed.

Lemma Sim_inj_exposed_hidden: 
  forall (F1 V1 C1 D1 G2 C2 D2: Type) 
   (csemS: CoreSemantics (Genv.t F1 V1) C1 mem D1)
   (csemT: CoreSemantics G2 C2 mem D2) ge1 ge2 
   entry_points core_data match_state core_ord,
  Sim_inj_exposed.Forward_simulation_inject D1 D2 csemS csemT ge1 ge2
    entry_points core_data match_state core_ord -> 
  Sim_inj.Forward_simulation_inject D1 D2 csemS csemT ge1 ge2 entry_points.
Proof.
intros until core_ord; intros []; intros.
solve[eapply @Sim_inj.Build_Forward_simulation_inject 
 with (core_data := core_data) (match_state := match_state); eauto].
Qed.

Lemma Sim_inj_hidden_exposed:
  forall (F1 V1 C1 D1 G2 C2 D2: Type) 
   (csemS: CoreSemantics (Genv.t F1 V1) C1 mem D1)
   (csemT: CoreSemantics G2 C2 mem D2) ge1 ge2 entry_points,
  Sim_inj.Forward_simulation_inject D1 D2 csemS csemT ge1 ge2 entry_points -> 
  {core_data: Type & 
  {match_state: core_data -> meminj -> C1 -> mem -> C2 -> mem -> Prop &
  {core_ord: core_data -> core_data -> Prop & 
    Sim_inj_exposed.Forward_simulation_inject D1 D2 csemS csemT ge1 ge2
    entry_points core_data match_state core_ord}}}.
Proof.
intros until entry_points; intros []; intros.
solve[eexists; eexists; eexists;
 eapply @Sim_inj_exposed.Build_Forward_simulation_inject; eauto].
Qed.

(*
Section PRECISE_MATCH_PROGRAM.
(*Adapted  from Compcert.AST.MATCH_PROGRAM - but we think we actually don't need this notion, 
hence have commented the corresponding clauses below in cc_eq and cc_ext.*)

Variable F1 F2 V1 V2: Type.

Inductive precise_match_funct_entry: ident * F1 -> ident * F2 -> Prop :=
  | precise_match_funct_entry_intro: forall id fn1 fn2,
       precise_match_funct_entry (id, fn1) (id, fn2).

Inductive precise_match_var_entry: ident * globvar V1 -> ident * globvar V2 -> Prop :=
  | precise_match_var_entry_intro: forall id info1 info2 init ro vo,
      precise_match_var_entry (id, mkglobvar info1 init ro vo)
                      (id, mkglobvar info2 init ro vo).

Definition precise_match_program  (P1: AST.program F1 V1)  (P2: AST.program F2 V2) : Prop :=
                (list_forall2 precise_match_funct_entry P1.(prog_funct) (P2.(prog_funct))) /\
                (list_forall2 precise_match_var_entry P1.(prog_vars) (P2.(prog_vars))) /\ 
                P2.(prog_main) = P1.(prog_main).

End PRECISE_MATCH_PROGRAM.
*)

Lemma forall_inject_val_list_inject: forall j args args' (H:Forall2 (val_inject j) args args' ),   val_list_inject j args args'.
  Proof.
    intros j args.
    induction args; intros;  inv H; constructor; eauto.
  Qed. 
Lemma val_list_inject_forall_inject: forall j args args' (H:val_list_inject j args args'), Forall2 (val_inject j) args args' .
  Proof.
    intros j args.
    induction args; intros;  inv H; constructor; eauto.
  Qed. 

Lemma forall_lessdef_val_listless: forall args args' (H: Forall2 Val.lessdef args args'),  Val.lessdef_list args args' .
  Proof.
    intros args.
    induction args; intros;  inv H; constructor; eauto.
  Qed. 
Lemma val_listless_forall_lessdef: forall args args' (H:Val.lessdef_list args args'), Forall2 Val.lessdef args args' .
  Proof.
    intros args.
    induction args; intros;  inv H; constructor; eauto.
  Qed. 


Module CompilerCorrectness.

Definition globvar_eq {V1 V2: Type} (v1:globvar V1) (v2:globvar V2) :=
    match v1, v2 with mkglobvar _ init1 readonly1 volatile1, mkglobvar _ init2 readonly2 volatile2 =>
                        init1 = init2 /\ readonly1 =  readonly2 /\ volatile1 = volatile2
   end.

Inductive external_description :=
   extern_func: signature -> external_description
| extern_globvar : external_description.

Definition entryPts_ok  {F1 V1 F2 V2:Type}  (P1 : AST.program F1 V1)    (P2 : AST.program F2 V2) 
                                       (ExternIdents : list (ident * external_description)) (entryPts: list (val * val * signature)): Prop :=
          forall e d, In (e,d) ExternIdents ->
                              exists b, Genv.find_symbol  (Genv.globalenv P1) e = Some b /\
                                             Genv.find_symbol (Genv.globalenv P2) e = Some b /\
                                             match d with
                                                      extern_func sig => In (Vptr b Int.zero,Vptr b Int.zero, sig) entryPts /\
                                                                                     exists f1, exists f2, Genv.find_funct_ptr (Genv.globalenv P1) b = Some f1 /\ 
                                                                                                                      Genv.find_funct_ptr (Genv.globalenv P2) b = Some f2
                                                    | extern_globvar  => exists v1, exists v2, Genv.find_var_info  (Genv.globalenv P1) b = Some v1 /\
                                                                                                                    Genv.find_var_info  (Genv.globalenv P2) b = Some v2 /\
                                                                                                                    globvar_eq v1 v2
                                             end.

Definition entryPts_inject_ok  {F1 V1 F2 V2:Type}  (P1 : AST.program F1 V1)    (P2 : AST.program F2 V2)  (j: meminj)
                                       (ExternIdents : list (ident * external_description)) (entryPts: list (val * val * signature)): Prop :=
          forall e d, In (e,d) ExternIdents ->
                              exists b1, exists b2, Genv.find_symbol (Genv.globalenv P1) e = Some b1 /\
                                                                Genv.find_symbol (Genv.globalenv P2) e = Some b2 /\
                                                                j b1 = Some(b2,0) /\
                                             match d with
                                                      extern_func sig => In (Vptr b1 Int.zero,Vptr b2 Int.zero, sig) entryPts /\
                                                                                     exists f1, exists f2, Genv.find_funct_ptr (Genv.globalenv P1) b1 = Some f1 /\ 
                                                                                                                      Genv.find_funct_ptr (Genv.globalenv P2) b2 = Some f2
                                                    | extern_globvar  => exists v1, exists v2, Genv.find_var_info  (Genv.globalenv P1) b1 = Some v1 /\
                                                                                                                    Genv.find_var_info  (Genv.globalenv P2) b2 = Some v2 /\
                                                                                                                    globvar_eq v1 v2
                                             end.

Definition externvars_ok  {F1 V1:Type}  (P1 : AST.program F1 V1) 
                                             (ExternIdents : list (ident * external_description)) : Prop :=
         forall b v, Genv.find_var_info  (Genv.globalenv P1) b = Some v -> 
                        exists e, Genv.find_symbol (Genv.globalenv P1) e = Some b /\ In (e,extern_globvar) ExternIdents.

Definition GenvHyp {F1 V1 F2 V2} 
               (P1 : AST.program F1 V1) (P2 : AST.program F2 V2): Prop :=
       (forall id : ident,
                                 Genv.find_symbol (Genv.globalenv P2) id =
                                 Genv.find_symbol (Genv.globalenv P1) id)
       /\ (forall b : block,
                                          block_is_volatile (Genv.globalenv P2) b =
                                          block_is_volatile (Genv.globalenv P1) b).

Inductive core_correctness (I: forall F C V  (Sem : CoreSemantics (Genv.t F V) C mem (list (ident * globdef F V)))  (P : AST.program F V),Prop)
        (ExternIdents: list (ident * external_description)):
       forall (F1 C1 V1 F2 C2 V2:Type)
               (Sem1 : CoreSemantics (Genv.t F1 V1) C1 mem (list (ident * globdef F1 V1)))
               (Sem2 : CoreSemantics (Genv.t F2 V2) C2 mem (list (ident * globdef F2 V2)))
               (P1 : AST.program F1 V1)
               (P2 : AST.program F2 V2), Type :=
   corec_eq : forall  (F1 C1 V1 F2 C2 V2:Type)
               (Sem1 : CoreSemantics (Genv.t F1 V1) C1 mem (list (ident * globdef F1 V1)))
               (Sem2 : CoreSemantics (Genv.t F2 V2) C2 mem (list (ident * globdef F2 V2)))
               (P1 : AST.program F1 V1)
               (P2 : AST.program F2 V2)
 (*              (match_prog:  precise_match_program F1 F2 V1 V2 P1 P2)*)
               (Eq_init: forall m1, initial_mem Sem1  (Genv.globalenv P1)  m1 P1.(prog_defs)->
                     (exists m2, initial_mem Sem2  (Genv.globalenv P2)  m2 P2.(prog_defs)
                                        /\ m1 = m2))
               entrypoints
               (ePts_ok: entryPts_ok P1 P2 ExternIdents entrypoints)
               (R:Sim_eq.Forward_simulation_equals _ _ _ Sem1 Sem2 (Genv.globalenv P1) (Genv.globalenv P2)  entrypoints), 
               prog_main P1 = prog_main P2 -> 

(*HERE IS THE INJECTION OF THE GENV-ASSUMPTIONS INTO THE PROOF:*)
               GenvHyp P1 P2 ->

                I _ _ _  Sem1 P1 -> I _ _ _  Sem2 P2 -> 
               core_correctness I ExternIdents F1 C1 V1 F2 C2 V2 Sem1 Sem2 P1 P2
 |  corec_ext : forall  (F1 C1 V1 F2 C2 V2:Type)
               (Sem1 : CoreSemantics (Genv.t F1 V1) C1 mem (list (ident * globdef F1 V1)))
               (Sem2 : CoreSemantics (Genv.t F2 V2) C2 mem (list (ident * globdef F2 V2)))
               (P1 : AST.program F1 V1)
               (P2 : AST.program F2 V2)
(*               (match_prog:  precise_match_program F1 F2 V1 V2 P1 P2)*)
               (Extends_init: forall m1, initial_mem Sem1  (Genv.globalenv P1)  m1 P1.(prog_defs)->
                     (exists m2, initial_mem Sem2  (Genv.globalenv P2)  m2 P2.(prog_defs) 
                                        /\ Mem.extends m1 m2))
               entrypoints
               (ePts_ok: entryPts_ok P1 P2 ExternIdents entrypoints)
               (R:Sim_ext.Forward_simulation_extends _ _ Sem1 Sem2 (Genv.globalenv P1) (Genv.globalenv P2)  entrypoints),
               prog_main P1 = prog_main P2 -> 

               (*HERE IS THE INJECTION OF THE GENV-ASSUMPTIONS INTO THE PROOF:*)
               GenvHyp P1 P2 ->

                I _ _ _ Sem1 P1 -> I _ _ _ Sem2 P2 -> 
               core_correctness I ExternIdents F1 C1 V1 F2 C2 V2 Sem1 Sem2 P1 P2
 |  corec_inj : forall  (F1 C1 V1 F2 C2 V2:Type)
               (Sem1 : CoreSemantics (Genv.t F1 V1) C1 mem (list (ident * globdef F1 V1)))
               (Sem2 : CoreSemantics (Genv.t F2 V2) C2 mem (list (ident * globdef F2 V2)))
               (P1 : AST.program F1 V1)
               (P2 : AST.program F2 V2)
               entrypoints jInit
               (Inj_init: forall m1, initial_mem Sem1  (Genv.globalenv P1)  m1 P1.(prog_defs)->
                     (exists m2, initial_mem Sem2  (Genv.globalenv P2)  m2 P2.(prog_defs)
                                        /\ Mem.inject jInit m1 m2))
               (ePts_ok: entryPts_inject_ok P1 P2 jInit ExternIdents entrypoints)
               (preserves_globals: meminj_preserves_globals (Genv.globalenv P1) jInit)
               (R:Sim_inj.Forward_simulation_inject _ _ Sem1 Sem2 
                 (Genv.globalenv P1) (Genv.globalenv P2) entrypoints),
               prog_main P1 = prog_main P2 ->

               (*HERE IS THE INJECTION OF THE GENV-ASSUMPTIONS INTO THE PROOF:*)
               GenvHyp P1 P2 ->
                externvars_ok P1 ExternIdents ->

                I _ _ _ Sem1 P1 -> I _ _ _ Sem2 P2 -> 
               core_correctness I ExternIdents F1 C1 V1 F2 C2 V2 Sem1 Sem2 P1 P2
 | corec_trans: forall  (F1 C1 V1 F2 C2 V2 F3 C3 V3:Type)
               (Sem1 : CoreSemantics (Genv.t F1 V1) C1 mem (list (ident * globdef F1 V1)))
               (Sem2 : CoreSemantics (Genv.t F2 V2) C2 mem (list (ident * globdef F2 V2)))
               (Sem3 : CoreSemantics (Genv.t F3 V3) C3 mem (list (ident * globdef F3 V3)))
               (P1 : AST.program F1 V1)
               (P2 : AST.program F2 V2)
               (P3 : AST.program F3 V3),
                 core_correctness I ExternIdents F1 C1 V1 F2 C2 V2 Sem1 Sem2 P1 P2 ->
                 core_correctness I ExternIdents F2 C2 V2 F3 C3 V3 Sem2 Sem3 P2 P3 ->
                 core_correctness I ExternIdents F1 C1 V1 F3 C3 V3 Sem1 Sem3 P1 P3.
 
Lemma corec_I: forall {F1 C1 V1 F2 C2 V2}
               (Sem1 : CoreSemantics (Genv.t F1 V1) C1 mem (list (ident * globdef F1 V1)))
               (Sem2 : CoreSemantics (Genv.t F2 V2) C2 mem (list (ident * globdef F2 V2)))
               (P1 : AST.program F1 V1)
               (P2 : AST.program F2 V2)  ExternIdents I,
                    core_correctness I ExternIdents F1 C1 V1 F2 C2 V2 Sem1 Sem2 P1 P2 ->
                     I _ _ _ Sem1 P1 /\ I _ _ _ Sem2 P2.
   Proof. intros. induction X; intuition. Qed.

Lemma corec_main: forall {F1 C1 V1 F2 C2 V2}
               (Sem1 : CoreSemantics (Genv.t F1 V1) C1 mem (list (ident * globdef F1 V1)))
               (Sem2 : CoreSemantics (Genv.t F2 V2) C2 mem (list (ident * globdef F2 V2)))
               (P1 : AST.program F1 V1)
               (P2 : AST.program F2 V2)  ExternIdents I,
                    core_correctness I ExternIdents F1 C1 V1 F2 C2 V2 Sem1 Sem2 P1 P2 ->
                    prog_main P1 = prog_main P2.
   Proof. intros. induction X; intuition. congruence. Qed.

(*TRANSITIVITY OF THE GENV-ASSUMPTIONS:*)
Lemma corec_Genv:forall {F1 C1 V1 F2 C2 V2}
               (Sem1 : CoreSemantics (Genv.t F1 V1) C1 mem (list (ident * globdef F1 V1)))
               (Sem2 : CoreSemantics (Genv.t F2 V2) C2 mem (list (ident * globdef F2 V2)))
               (P1 : AST.program F1 V1)
               (P2 : AST.program F2 V2)  ExternIdents I,
                    core_correctness I ExternIdents F1 C1 V1 F2 C2 V2 Sem1 Sem2 P1 P2 ->
               GenvHyp P1 P2.
   Proof. intros. induction X; intuition. 
       destruct IHX1.
       destruct IHX2.
        split; intros; eauto. rewrite H1. apply H. Qed.

(*And here the variant for CompcertCoreSemantics*)

Inductive compiler_correctness (I: forall F C V  (Sem : CompcertCoreSem (Genv.t F V) C  (list (ident * globdef F V)))  (P : AST.program F V),Prop)
        (ExternIdents: list (ident * external_description)):
       forall (F1 C1 V1 F2 C2 V2:Type)
               (Sem1 : CompcertCoreSem (Genv.t F1 V1) C1 (list (ident * globdef F1 V1)))
               (Sem2 : CompcertCoreSem (Genv.t F2 V2) C2 (list (ident * globdef F2 V2)))
               (P1 : AST.program F1 V1)
               (P2 : AST.program F2 V2), Type :=
   cc_eq : forall  (F1 C1 V1 F2 C2 V2:Type)
               (Sem1 : CompcertCoreSem (Genv.t F1 V1) C1 (list (ident * globdef F1 V1)))
               (Sem2 : CompcertCoreSem (Genv.t F2 V2) C2 (list (ident * globdef F2 V2)))
               (P1 : AST.program F1 V1)
               (P2 : AST.program F2 V2)
 (*              (match_prog:  precise_match_program F1 F2 V1 V2 P1 P2)*)
               (Eq_init: forall m1, initial_mem Sem1  (Genv.globalenv P1)  m1 P1.(prog_defs)->
                     (exists m2, initial_mem Sem2  (Genv.globalenv P2)  m2 P2.(prog_defs)
                                        /\ m1 = m2))
               entrypoints
               (ePts_ok: entryPts_ok P1 P2 ExternIdents entrypoints)
               (R:Sim_eq.Forward_simulation_equals _ _ _ Sem1 Sem2 (Genv.globalenv P1) (Genv.globalenv P2)  entrypoints), 
               prog_main P1 = prog_main P2 -> 

(*HERE IS THE INJECTION OF THE GENV-ASSUMPTIONS INTO THE PROOF:*)
               GenvHyp P1 P2 ->

                I _ _ _  Sem1 P1 -> I _ _ _  Sem2 P2 -> 
               compiler_correctness I ExternIdents F1 C1 V1 F2 C2 V2 Sem1 Sem2 P1 P2
 |  cc_ext : forall  (F1 C1 V1 F2 C2 V2:Type)
               (Sem1 : CompcertCoreSem (Genv.t F1 V1) C1 (list (ident * globdef F1 V1)))
               (Sem2 : CompcertCoreSem (Genv.t F2 V2) C2 (list (ident * globdef F2 V2)))
               (P1 : AST.program F1 V1)
               (P2 : AST.program F2 V2)
(*               (match_prog:  precise_match_program F1 F2 V1 V2 P1 P2)*)
               (Extends_init: forall m1, initial_mem Sem1  (Genv.globalenv P1)  m1 P1.(prog_defs)->
                     (exists m2, initial_mem Sem2  (Genv.globalenv P2)  m2 P2.(prog_defs) 
                                        /\ Mem.extends m1 m2))
               entrypoints
               (ePts_ok: entryPts_ok P1 P2 ExternIdents entrypoints)
               (R:Sim_ext.Forward_simulation_extends _ _ Sem1 Sem2 (Genv.globalenv P1) (Genv.globalenv P2)  entrypoints),
               prog_main P1 = prog_main P2 -> 

               (*HERE IS THE INJECTION OF THE GENV-ASSUMPTIONS INTO THE PROOF:*)
               GenvHyp P1 P2 ->

                I _ _ _ Sem1 P1 -> I _ _ _ Sem2 P2 -> 
               compiler_correctness I ExternIdents F1 C1 V1 F2 C2 V2 Sem1 Sem2 P1 P2
 |  cc_inj : forall  (F1 C1 V1 F2 C2 V2:Type)
               (Sem1 : CompcertCoreSem (Genv.t F1 V1) C1 (list (ident * globdef F1 V1)))
               (Sem2 : CompcertCoreSem (Genv.t F2 V2) C2 (list (ident * globdef F2 V2)))
               (P1 : AST.program F1 V1)
               (P2 : AST.program F2 V2)
               entrypoints jInit
               (Inj_init: forall m1, initial_mem Sem1  (Genv.globalenv P1)  m1 P1.(prog_defs)->
                     (exists m2, initial_mem Sem2  (Genv.globalenv P2)  m2 P2.(prog_defs)
                                        /\ Mem.inject jInit m1 m2))
               (ePts_ok: entryPts_inject_ok P1 P2 jInit ExternIdents entrypoints)
               (preserves_globals: meminj_preserves_globals (Genv.globalenv P1) jInit)
               (R:Sim_inj.Forward_simulation_inject _ _ Sem1 Sem2 
                 (Genv.globalenv P1) (Genv.globalenv P2) entrypoints), 
               prog_main P1 = prog_main P2 ->

               (*HERE IS THE INJECTION OF THE GENV-ASSUMPTIONS INTO THE PROOF:*)
               GenvHyp P1 P2 ->
                externvars_ok P1 ExternIdents ->

                I _ _ _ Sem1 P1 -> I _ _ _ Sem2 P2 -> 
               compiler_correctness I ExternIdents F1 C1 V1 F2 C2 V2 Sem1 Sem2 P1 P2
 | cc_trans: forall  (F1 C1 V1 F2 C2 V2 F3 C3 V3:Type)
               (Sem1 : CompcertCoreSem (Genv.t F1 V1) C1 (list (ident * globdef F1 V1)))
               (Sem2 : CompcertCoreSem (Genv.t F2 V2) C2 (list (ident * globdef F2 V2)))
               (Sem3 : CompcertCoreSem (Genv.t F3 V3) C3 (list (ident * globdef F3 V3)))
               (P1 : AST.program F1 V1)
               (P2 : AST.program F2 V2)
               (P3 : AST.program F3 V3),
                 compiler_correctness I ExternIdents F1 C1 V1 F2 C2 V2 Sem1 Sem2 P1 P2 ->
                 compiler_correctness I ExternIdents F2 C2 V2 F3 C3 V3 Sem2 Sem3 P2 P3 ->
                 compiler_correctness I ExternIdents F1 C1 V1 F3 C3 V3 Sem1 Sem3 P1 P3.
 
Lemma cc_I: forall {F1 C1 V1 F2 C2 V2}
               (Sem1 : CompcertCoreSem (Genv.t F1 V1) C1 (list (ident * globdef F1 V1)))
               (Sem2 : CompcertCoreSem (Genv.t F2 V2) C2 (list (ident * globdef F2 V2)))
               (P1 : AST.program F1 V1)
               (P2 : AST.program F2 V2)  ExternIdents I,
                    compiler_correctness I ExternIdents F1 C1 V1 F2 C2 V2 Sem1 Sem2 P1 P2 ->
                     I _ _ _ Sem1 P1 /\ I _ _ _ Sem2 P2.
   Proof. intros. induction X; intuition. Qed.

Lemma cc_main: forall {F1 C1 V1 F2 C2 V2}
               (Sem1 : CompcertCoreSem (Genv.t F1 V1) C1 (list (ident * globdef F1 V1)))
               (Sem2 : CompcertCoreSem (Genv.t F2 V2) C2 (list (ident * globdef F2 V2)))
               (P1 : AST.program F1 V1)
               (P2 : AST.program F2 V2)  ExternIdents I,
                    compiler_correctness I ExternIdents F1 C1 V1 F2 C2 V2 Sem1 Sem2 P1 P2 ->
                    prog_main P1 = prog_main P2.
   Proof. intros. induction X; intuition. congruence. Qed.

(*TRANSITIVITY OF THE GENV-ASSUMPTIONS:*)
Lemma cc_Genv:forall {F1 C1 V1 F2 C2 V2}
               (Sem1 : CompcertCoreSem (Genv.t F1 V1) C1 (list (ident * globdef F1 V1)))
               (Sem2 : CompcertCoreSem (Genv.t F2 V2) C2 (list (ident * globdef F2 V2)))
               (P1 : AST.program F1 V1)
               (P2 : AST.program F2 V2)  ExternIdents I,
                    compiler_correctness I ExternIdents F1 C1 V1 F2 C2 V2 Sem1 Sem2 P1 P2 ->
               GenvHyp P1 P2.
   Proof. intros. induction X; intuition. 
       destruct IHX1.
       destruct IHX2.
        split; intros; eauto. rewrite H1. apply H. Qed.

Inductive cc_sim (I: forall F C V  (Sem : CoopCoreSem (Genv.t F V) C (list (ident * globdef F V)))  (P : AST.program F V),Prop)
        (ExternIdents: list (ident * external_description)) entrypoints:
       forall (F1 C1 V1 F2 C2 V2:Type)
               (Sem1 : CoopCoreSem (Genv.t F1 V1) C1 (list (ident * globdef F1 V1)))
               (Sem2 : CoopCoreSem (Genv.t F2 V2) C2 (list (ident * globdef F2 V2)))
               (P1 : AST.program F1 V1)
               (P2 : AST.program F2 V2), Type :=
   ccs_eq : forall  (F1 C1 V1 F2 C2 V2:Type)
               (Sem1 : CoopCoreSem (Genv.t F1 V1) C1 (list (ident * globdef F1 V1)))
               (Sem2 : CoopCoreSem (Genv.t F2 V2) C2 (list (ident * globdef F2 V2)))
               (P1 : AST.program F1 V1)
               (P2 : AST.program F2 V2)
 (*              (match_prog:  precise_match_program F1 F2 V1 V2 P1 P2)*)
               (Eq_init: forall m1, initial_mem Sem1  (Genv.globalenv P1)  m1 P1.(prog_defs)->
                     (exists m2, initial_mem Sem2  (Genv.globalenv P2)  m2 P2.(prog_defs)
                                        /\ m1 = m2))
               (ePts_ok: entryPts_ok P1 P2 ExternIdents entrypoints)
               (R:Sim_eq.Forward_simulation_equals _ _ _ Sem1 Sem2 (Genv.globalenv P1) (Genv.globalenv P2)  entrypoints), 
               prog_main P1 = prog_main P2 -> 

(*HERE IS THE INJECTION OF THE GENV-ASSUMPTIONS INTO THE PROOF:*)
               GenvHyp P1 P2 ->

                I _ _ _  Sem1 P1 -> I _ _ _  Sem2 P2 -> 
               cc_sim I ExternIdents  entrypoints F1 C1 V1 F2 C2 V2 Sem1 Sem2 P1 P2
 |  ccs_ext : forall  (F1 C1 V1 F2 C2 V2:Type)
               (Sem1 : CoopCoreSem (Genv.t F1 V1) C1 (list (ident * globdef F1 V1)))
               (Sem2 : CoopCoreSem (Genv.t F2 V2) C2 (list (ident * globdef F2 V2)))
               (P1 : AST.program F1 V1)
               (P2 : AST.program F2 V2)
(*               (match_prog:  precise_match_program F1 F2 V1 V2 P1 P2)*)
               (Extends_init: forall m1, initial_mem Sem1  (Genv.globalenv P1)  m1 P1.(prog_defs)->
                     (exists m2, initial_mem Sem2  (Genv.globalenv P2)  m2 P2.(prog_defs) 
                                        /\ Mem.extends m1 m2))
               (ePts_ok: entryPts_ok P1 P2 ExternIdents entrypoints)
               (R:CoopSim_ext.Forward_simulation_extends _ _ Sem1 Sem2 (Genv.globalenv P1) (Genv.globalenv P2)  entrypoints),
               prog_main P1 = prog_main P2 -> 

               (*HERE IS THE INJECTION OF THE GENV-ASSUMPTIONS INTO THE PROOF:*)
               GenvHyp P1 P2 ->

                I _ _ _ Sem1 P1 -> I _ _ _ Sem2 P2 -> 
               cc_sim I ExternIdents  entrypoints F1 C1 V1 F2 C2 V2 Sem1 Sem2 P1 P2
 |  ccs_inj : forall  (F1 C1 V1 F2 C2 V2:Type)
               (Sem1 : CoopCoreSem (Genv.t F1 V1) C1 (list (ident * globdef F1 V1)))
               (Sem2 : CoopCoreSem (Genv.t F2 V2) C2 (list (ident * globdef F2 V2)))
               (P1 : AST.program F1 V1)
               (P2 : AST.program F2 V2)
                jInit
               (Inj_init: forall m1, initial_mem Sem1  (Genv.globalenv P1)  m1 P1.(prog_defs)->
                     (exists m2, initial_mem Sem2  (Genv.globalenv P2)  m2 P2.(prog_defs)
                                        /\ Mem.inject jInit m1 m2))
               (ePts_ok: entryPts_inject_ok P1 P2 jInit ExternIdents entrypoints)
               (preserves_globals: meminj_preserves_globals (Genv.globalenv P1) jInit)
               (R:CoopSim_inj.Forward_simulation_inject _ _ Sem1 Sem2 
                 (Genv.globalenv P1) (Genv.globalenv P2)  entrypoints),
               prog_main P1 = prog_main P2 ->

               (*HERE IS THE INJECTION OF THE GENV-ASSUMPTIONS INTO THE PROOF:*)
               GenvHyp P1 P2 ->
                externvars_ok P1 ExternIdents ->

                I _ _ _ Sem1 P1 -> I _ _ _ Sem2 P2 -> 
               cc_sim I ExternIdents entrypoints  F1 C1 V1 F2 C2 V2 Sem1 Sem2 P1 P2.

End CompilerCorrectness.

    