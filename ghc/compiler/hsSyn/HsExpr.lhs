%
% (c) The GRASP/AQUA Project, Glasgow University, 1992-1998
%
\section[HsExpr]{Abstract Haskell syntax: expressions}

\begin{code}
module HsExpr where

#include "HsVersions.h"

-- friends:
import {-# SOURCE #-} HsMatches ( pprMatches, pprMatch, Match )

import HsBinds		( HsBinds(..) )
import HsLit		( HsLit, HsOverLit )
import BasicTypes	( Fixity(..) )
import HsTypes		( HsType )

-- others:
import Name		( Name, isLexSym ) 
import Outputable	
import PprType		( pprType, pprParendType )
import Type		( Type )
import Var		( TyVar )
import DataCon		( DataCon )
import CStrings		( CLabelString, pprCLabelString )
import BasicTypes	( Boxity, tupleParens )
import SrcLoc		( SrcLoc )
\end{code}

%************************************************************************
%*									*
\subsection{Expressions proper}
%*									*
%************************************************************************

\begin{code}
data HsExpr id pat
  = HsVar	id		-- variable
  | HsIPVar	id		-- implicit parameter
  | HsOverLit	(HsOverLit id)	-- Overloaded literals; eliminated by type checker
  | HsLit	HsLit		-- Simple (non-overloaded) literals

  | HsLam	(Match  id pat)	-- lambda
  | HsApp	(HsExpr id pat)	-- application
		(HsExpr id pat)

  -- Operator applications:
  -- NB Bracketed ops such as (+) come out as Vars.

  -- NB We need an expr for the operator in an OpApp/Section since
  -- the typechecker may need to apply the operator to a few types.

  | OpApp	(HsExpr id pat)	-- left operand
		(HsExpr id pat)	-- operator
		Fixity				-- Renamer adds fixity; bottom until then
		(HsExpr id pat)	-- right operand

  -- We preserve prefix negation and parenthesis for the precedence parser.
  -- They are eventually removed by the type checker.

  | NegApp	(HsExpr id pat)	-- negated expr
		id 		-- the negate id (in a HsVar)

  | HsPar	(HsExpr id pat)	-- parenthesised expr

  | SectionL	(HsExpr id pat)	-- operand
		(HsExpr id pat)	-- operator
  | SectionR	(HsExpr id pat)	-- operator
		(HsExpr id pat)	-- operand
				
  | HsCase	(HsExpr id pat)
		[Match id pat]
		SrcLoc

  | HsIf	(HsExpr id pat)	--  predicate
		(HsExpr id pat)	--  then part
		(HsExpr id pat)	--  else part
		SrcLoc

  | HsLet	(HsBinds id pat)	-- let(rec)
		(HsExpr  id pat)

  | HsWith	(HsExpr id pat)	-- implicit parameter binding
  		[(id, HsExpr id pat)]

  | HsDo	StmtCtxt
		[Stmt id pat]	-- "do":one or more stmts
		SrcLoc

  | HsDoOut	StmtCtxt
		[Stmt id pat]	-- "do":one or more stmts
		id		-- id for return
		id		-- id for >>=
		id				-- id for zero
		Type		-- Type of the whole expression
		SrcLoc

  | ExplicitList		-- syntactic list
		[HsExpr id pat]
  | ExplicitListOut		-- TRANSLATION
		Type	-- Gives type of components of list
		[HsExpr id pat]

  | ExplicitTuple		-- tuple
		[HsExpr id pat]
				-- NB: Unit is ExplicitTuple []
				-- for tuples, we can get the types
				-- direct from the components
		Boxity


	-- Record construction
  | RecordCon	id				-- The constructor
		(HsRecordBinds id pat)

  | RecordConOut DataCon
		(HsExpr id pat)		-- Data con Id applied to type args
		(HsRecordBinds id pat)


	-- Record update
  | RecordUpd	(HsExpr id pat)
		(HsRecordBinds id pat)

  | RecordUpdOut (HsExpr id pat)	-- TRANSLATION
		 Type			-- Type of *result* record (may differ from
						-- type of input record)
		 [id]			-- Dicts needed for construction
		 (HsRecordBinds id pat)

  | ExprWithTySig			-- signature binding
		(HsExpr id pat)
		(HsType id)
  | ArithSeqIn				-- arithmetic sequence
		(ArithSeqInfo id pat)
  | ArithSeqOut
		(HsExpr id pat)		-- (typechecked, of course)
		(ArithSeqInfo id pat)

  | HsCCall	CLabelString	-- call into the C world; string is
		[HsExpr id pat]	-- the C function; exprs are the
				-- arguments to pass.
		Bool		-- True <=> might cause Haskell
				-- garbage-collection (must generate
				-- more paranoid code)
		Bool		-- True <=> it's really a "casm"
				-- NOTE: this CCall is the *boxed*
				-- version; the desugarer will convert
				-- it into the unboxed "ccall#".
		Type	-- The result type; will be *bottom*
				-- until the typechecker gets ahold of it

  | HsSCC	FAST_STRING	-- "set cost centre" (_scc_) annotation
		(HsExpr id pat) -- expr whose cost is to be measured
\end{code}

These constructors only appear temporarily in the parser.
The renamer translates them into the Right Thing.

\begin{code}
  | EWildPat			-- wildcard

  | EAsPat	id		-- as pattern
		(HsExpr id pat)

  | ELazyPat	(HsExpr id pat) -- ~ pattern
\end{code}

Everything from here on appears only in typechecker output.

\begin{code}
  | TyLam			-- TRANSLATION
		[TyVar]
		(HsExpr id pat)
  | TyApp			-- TRANSLATION
		(HsExpr id pat) -- generated by Spec
		[Type]

  -- DictLam and DictApp are "inverses"
  |  DictLam
		[id]
		(HsExpr id pat)
  |  DictApp
		(HsExpr id pat)
		[id]

type HsRecordBinds id pat
  = [(id, HsExpr id pat, Bool)]
	-- True <=> source code used "punning",
	-- i.e. {op1, op2} rather than {op1=e1, op2=e2}
\end{code}

A @Dictionary@, unless of length 0 or 1, becomes a tuple.  A
@ClassDictLam dictvars methods expr@ is, therefore:
\begin{verbatim}
\ x -> case x of ( dictvars-and-methods-tuple ) -> expr
\end{verbatim}

\begin{code}
instance (Outputable id, Outputable pat) =>
		Outputable (HsExpr id pat) where
    ppr expr = pprExpr expr
\end{code}

\begin{code}
pprExpr :: (Outputable id, Outputable pat)
        => HsExpr id pat -> SDoc

pprExpr e = pprDeeper (ppr_expr e)
pprBinds b = pprDeeper (ppr b)

ppr_expr (HsVar v) 
	-- Put it in parens if it's an operator
  | isOperator v = parens (ppr v)
  | otherwise    = ppr v

ppr_expr (HsIPVar v)     = {- char '?' <> -} ppr v
ppr_expr (HsLit lit)     = ppr lit
ppr_expr (HsOverLit lit) = ppr lit

ppr_expr (HsLam match)
  = hsep [char '\\', nest 2 (pprMatch (True,empty) match)]

ppr_expr expr@(HsApp e1 e2)
  = let (fun, args) = collect_args expr [] in
    (ppr_expr fun) <+> (sep (map ppr_expr args))
  where
    collect_args (HsApp fun arg) args = collect_args fun (arg:args)
    collect_args fun		 args = (fun, args)

ppr_expr (OpApp e1 op fixity e2)
  = case op of
      HsVar v -> pp_infixly v
      _	      -> pp_prefixly
  where
    pp_e1 = pprParendExpr e1		-- Add parens to make precedence clear
    pp_e2 = pprParendExpr e2

    pp_prefixly
      = hang (pprExpr op) 4 (sep [pp_e1, pp_e2])

    pp_infixly v
      = sep [pp_e1, hsep [pp_v_op, pp_e2]]
      where
        pp_v_op | isOperator v = ppr v
		| otherwise    = char '`' <> ppr v <> char '`'
	        -- Put it in backquotes if it's not an operator already

ppr_expr (NegApp e _) = char '-' <+> pprParendExpr e

ppr_expr (HsPar e) = parens (ppr_expr e)

ppr_expr (SectionL expr op)
  = case op of
      HsVar v -> pp_infixly v
      _	      -> pp_prefixly
  where
    pp_expr = pprParendExpr expr

    pp_prefixly = hang (hsep [text " \\ x_ ->", ppr op])
		       4 (hsep [pp_expr, ptext SLIT("x_ )")])
    pp_infixly v = parens (sep [pp_expr, ppr v])

ppr_expr (SectionR op expr)
  = case op of
      HsVar v -> pp_infixly v
      _	      -> pp_prefixly
  where
    pp_expr = pprParendExpr expr

    pp_prefixly = hang (hsep [text "( \\ x_ ->", ppr op, ptext SLIT("x_")])
		       4 ((<>) pp_expr rparen)
    pp_infixly v
      = parens (sep [ppr v, pp_expr])

ppr_expr (HsCase expr matches _)
  = sep [ sep [ptext SLIT("case"), nest 4 (pprExpr expr), ptext SLIT("of")],
	    nest 2 (pprMatches (True, empty) matches) ]

ppr_expr (HsIf e1 e2 e3 _)
  = sep [hsep [ptext SLIT("if"), nest 2 (pprExpr e1), ptext SLIT("then")],
	   nest 4 (pprExpr e2),
	   ptext SLIT("else"),
	   nest 4 (pprExpr e3)]

-- special case: let ... in let ...
ppr_expr (HsLet binds expr@(HsLet _ _))
  = sep [hang (ptext SLIT("let")) 2 (hsep [pprBinds binds, ptext SLIT("in")]),
	 pprExpr expr]

ppr_expr (HsLet binds expr)
  = sep [hang (ptext SLIT("let")) 2 (pprBinds binds),
	 hang (ptext SLIT("in"))  2 (ppr expr)]

ppr_expr (HsWith expr binds)
  = hsep [ppr expr, ptext SLIT("with"), ppr binds]

ppr_expr (HsDo do_or_list_comp stmts _)            = pprDo do_or_list_comp stmts
ppr_expr (HsDoOut do_or_list_comp stmts _ _ _ _ _) = pprDo do_or_list_comp stmts

ppr_expr (ExplicitList exprs)
  = brackets (fsep (punctuate comma (map ppr_expr exprs)))
ppr_expr (ExplicitListOut ty exprs)
  = hcat [ brackets (fsep (punctuate comma (map ppr_expr exprs))),
	   ifNotPprForUser ((<>) space (parens (pprType ty))) ]

ppr_expr (ExplicitTuple exprs boxity)
  = tupleParens boxity (sep (punctuate comma (map ppr_expr exprs)))

ppr_expr (RecordCon con_id rbinds)
  = pp_rbinds (ppr con_id) rbinds
ppr_expr (RecordConOut data_con con rbinds)
  = pp_rbinds (ppr con) rbinds

ppr_expr (RecordUpd aexp rbinds)
  = pp_rbinds (pprParendExpr aexp) rbinds
ppr_expr (RecordUpdOut aexp _ _ rbinds)
  = pp_rbinds (pprParendExpr aexp) rbinds

ppr_expr (ExprWithTySig expr sig)
  = hang (nest 2 (ppr_expr expr) <+> dcolon)
	 4 (ppr sig)

ppr_expr (ArithSeqIn info)
  = brackets (ppr info)
ppr_expr (ArithSeqOut expr info)
  = brackets (ppr info)

ppr_expr EWildPat = char '_'
ppr_expr (ELazyPat e) = char '~' <> pprParendExpr e
ppr_expr (EAsPat v e) = ppr v <> char '@' <> pprParendExpr e

ppr_expr (HsCCall fun args _ is_asm result_ty)
  = hang (if is_asm
	  then ptext SLIT("_casm_ ``") <> pprCLabelString fun <> ptext SLIT("''")
	  else ptext SLIT("_ccall_") <+> pprCLabelString fun)
       4 (sep (map pprParendExpr args))

ppr_expr (HsSCC lbl expr)
  = sep [ ptext SLIT("_scc_") <+> doubleQuotes (ptext lbl), pprParendExpr expr ]

ppr_expr (TyLam tyvars expr)
  = hang (hsep [ptext SLIT("/\\"), interppSP tyvars, ptext SLIT("->")])
	 4 (ppr_expr expr)

ppr_expr (TyApp expr [ty])
  = hang (ppr_expr expr) 4 (pprParendType ty)

ppr_expr (TyApp expr tys)
  = hang (ppr_expr expr)
	 4 (brackets (interpp'SP tys))

ppr_expr (DictLam dictvars expr)
  = hang (hsep [ptext SLIT("\\{-dict-}"), interppSP dictvars, ptext SLIT("->")])
	 4 (ppr_expr expr)

ppr_expr (DictApp expr [dname])
  = hang (ppr_expr expr) 4 (ppr dname)

ppr_expr (DictApp expr dnames)
  = hang (ppr_expr expr)
	 4 (brackets (interpp'SP dnames))

\end{code}

Parenthesize unless very simple:
\begin{code}
pprParendExpr :: (Outputable id, Outputable pat)
	      => HsExpr id pat -> SDoc

pprParendExpr expr
  = let
	pp_as_was = pprExpr expr
    in
    case expr of
      HsLit l		    -> ppr l
      HsOverLit l 	    -> ppr l

      HsVar _		    -> pp_as_was
      HsIPVar _		    -> pp_as_was
      ExplicitList _	    -> pp_as_was
      ExplicitListOut _ _   -> pp_as_was
      ExplicitTuple _ _	    -> pp_as_was
      HsPar _		    -> pp_as_was

      _			    -> parens pp_as_was
\end{code}

\begin{code}
isOperator :: Outputable a => a -> Bool
isOperator v = isLexSym (_PK_ (showSDoc (ppr v)))
	-- We use (showSDoc (ppr v)), rather than isSymOcc (getOccName v) simply so
	-- that we don't need NamedThing in the context of all these functions.
	-- Gruesome, but simple.
\end{code}

%************************************************************************
%*									*
\subsection{Record binds}
%*									*
%************************************************************************

\begin{code}
pp_rbinds :: (Outputable id, Outputable pat)
	      => SDoc 
	      -> HsRecordBinds id pat -> SDoc

pp_rbinds thing rbinds
  = hang thing 
	 4 (braces (sep (punctuate comma (map (pp_rbind) rbinds))))
  where
    pp_rbind (v, e, pun_flag) 
      = getPprStyle $ \ sty ->
        if pun_flag && userStyle sty then
	   ppr v
	else
	   hsep [ppr v, char '=', ppr e]
\end{code}

%************************************************************************
%*									*
\subsection{Do stmts and list comprehensions}
%*									*
%************************************************************************

\begin{code}
data StmtCtxt	-- Context of a Stmt
  = DoStmt		-- Do Statment
  | ListComp		-- List comprehension
  | CaseAlt		-- Guard on a case alternative
  | PatBindRhs		-- Guard on a pattern binding
  | FunRhs Name		-- Guard on a function defn for f
  | LambdaBody		-- Body of a lambda abstraction
		
pprDo DoStmt stmts
  = hang (ptext SLIT("do")) 2 (vcat (map ppr stmts))
pprDo ListComp stmts
  = brackets $
    hang (pprExpr expr <+> char '|')
       4 (interpp'SP quals)
  where
    ReturnStmt expr = last stmts	-- Last stmt should be a ReturnStmt for list comps
    quals	    = init stmts
\end{code}

\begin{code}
data Stmt id pat
  = BindStmt	pat
		(HsExpr id pat)
		SrcLoc

  | LetStmt	(HsBinds id pat)

  | GuardStmt	(HsExpr id pat)		-- List comps only
		SrcLoc

  | ExprStmt	(HsExpr id pat)		-- Do stmts; and guarded things at the end
		SrcLoc

  | ReturnStmt	(HsExpr id pat)		-- List comps only, at the end

consLetStmt :: HsBinds id pat -> [Stmt id pat] -> [Stmt id pat]
consLetStmt EmptyBinds stmts = stmts
consLetStmt binds      stmts = LetStmt binds : stmts
\end{code}

\begin{code}
instance (Outputable id, Outputable pat) =>
		Outputable (Stmt id pat) where
    ppr stmt = pprStmt stmt

pprStmt (BindStmt pat expr _)
 = hsep [ppr pat, ptext SLIT("<-"), ppr expr]
pprStmt (LetStmt binds)
 = hsep [ptext SLIT("let"), pprBinds binds]
pprStmt (ExprStmt expr _)
 = ppr expr
pprStmt (GuardStmt expr _)
 = ppr expr
pprStmt (ReturnStmt expr)
 = hsep [ptext SLIT("return"), ppr expr]    
\end{code}

%************************************************************************
%*									*
\subsection{Enumerations and list comprehensions}
%*									*
%************************************************************************

\begin{code}
data ArithSeqInfo id pat
  = From	    (HsExpr id pat)
  | FromThen 	    (HsExpr id pat)
		    (HsExpr id pat)
  | FromTo	    (HsExpr id pat)
		    (HsExpr id pat)
  | FromThenTo	    (HsExpr id pat)
		    (HsExpr id pat)
		    (HsExpr id pat)
\end{code}

\begin{code}
instance (Outputable id, Outputable pat) =>
		Outputable (ArithSeqInfo id pat) where
    ppr (From e1)		= hcat [ppr e1, pp_dotdot]
    ppr (FromThen e1 e2)	= hcat [ppr e1, comma, space, ppr e2, pp_dotdot]
    ppr (FromTo e1 e3)	= hcat [ppr e1, pp_dotdot, ppr e3]
    ppr (FromThenTo e1 e2 e3)
      = hcat [ppr e1, comma, space, ppr e2, pp_dotdot, ppr e3]

pp_dotdot = ptext SLIT(" .. ")
\end{code}
