{-# LANGUAGE FlexibleInstances    #-}
{-# LANGUAGE TypeSynonymInstances #-}

{- |
Module      : Language.Egison.RState
Licence     : MIT

This module defines runtime state.
-}

module Language.Egison.RState
    ( RState (..)
    , RuntimeT
    , RuntimeM
    , MonadRuntime (..)
    , runRuntimeT
    , evalRuntimeT
    ) where

import           Control.Monad.Trans.Class        (lift)
import           Control.Monad.Trans.Reader
import           Control.Monad.Trans.State.Strict

import           Language.Egison.AST
import           Language.Egison.CmdOptions

--
-- Runtime State
--

data RState = RState
  { indexCounter :: Int
  , exprInfixes :: [Infix]
  , patternInfixes :: [Infix]
  }

initialRState :: RState
initialRState = RState
  { indexCounter = 0
  , exprInfixes = reservedExprInfix
  , patternInfixes = reservedPatternInfix
  }

type RuntimeT m = ReaderT EgisonOpts (StateT RState m)

type RuntimeM = RuntimeT IO

class (Applicative m, Monad m) => MonadRuntime m where
  fresh :: m String
  freshV :: m Var

instance Monad m => MonadRuntime (RuntimeT m) where
  fresh = do
    st <- lift get
    lift (modify (\st -> st { indexCounter = indexCounter st + 1 }))
    return $ "$_" ++ show (indexCounter st)
  freshV = do
    st <- lift get
    lift (modify (\st -> st {indexCounter = indexCounter st + 1 }))
    return $ Var ["$_" ++ show (indexCounter st)] []

runRuntimeT :: Monad m => EgisonOpts -> RuntimeT m a -> m (a, RState)
runRuntimeT opts = flip runStateT initialRState . flip runReaderT opts

evalRuntimeT :: Monad m => EgisonOpts -> RuntimeT m a -> m a
evalRuntimeT opts = flip evalStateT initialRState . flip runReaderT opts