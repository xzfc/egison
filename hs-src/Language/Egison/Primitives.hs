{-# Language FlexibleContexts #-}

{- |
Module      : Language.Egison.Primitives
Copyright   : Satoshi Egi
Licence     : MIT

This module provides primitive functions in Egison.
-}

module Language.Egison.Primitives (primitiveEnv, primitiveEnvNoIO) where

import Control.Arrow
import Control.Monad.Error
import Control.Monad.Trans.Maybe
import Control.Applicative ((<$>), (<*>), (*>), (<*), pure)

import Data.IORef
import Data.Ratio
import Data.Foldable (toList)
import Text.Regex.TDFA

import System.IO
import System.Random
import System.Process

import qualified Data.Sequence as Sq

import Data.Char (ord, chr)
import qualified Data.Text as T
import Data.Text (Text)
import qualified Data.Text.IO as T

 {--  -- for 'egison-sqlite'
import qualified Database.SQLite3 as SQLite
 --}  -- for 'egison-sqlite'

import Language.Egison.Types
import Language.Egison.Parser
import Language.Egison.Core

primitiveEnv :: IO Env
primitiveEnv = do
  let ops = map (second PrimitiveFunc) (primitives ++ ioPrimitives)
  bindings <- forM (constants ++ ops) $ \(name, op) -> do
    ref <- newIORef . WHNF $ Value op
    return (name, ref)
  return $ extendEnv nullEnv bindings

primitiveEnvNoIO :: IO Env
primitiveEnvNoIO = do
  let ops = map (second PrimitiveFunc) primitives
  bindings <- forM (constants ++ ops) $ \(name, op) -> do
    ref <- newIORef . WHNF $ Value op
    return (name, ref)
  return $ extendEnv nullEnv bindings

{-# INLINE noArg #-}
noArg :: EgisonM EgisonValue -> PrimitiveFunc
noArg f = \args -> do
  args' <- tupleToList args
  case args' of 
    [] -> f >>= return . Value
    _ -> throwError $ ArgumentsNumPrimitive 0 $ length args'

{-# INLINE oneArg #-}
oneArg :: (EgisonValue -> EgisonM EgisonValue) -> PrimitiveFunc
oneArg f = \args -> do
  args' <- evalWHNF args
  f args' >>= return . Value

{-# INLINE twoArgs #-}
twoArgs :: (EgisonValue -> EgisonValue -> EgisonM EgisonValue) -> PrimitiveFunc
twoArgs f = \args -> do
  args' <- tupleToList args
  case args' of 
    [val, val'] -> f val val' >>= return . Value
    _ -> throwError $ ArgumentsNumPrimitive 2 $ length args'

{-# INLINE threeArgs #-}
threeArgs :: (EgisonValue -> EgisonValue -> EgisonValue -> EgisonM EgisonValue) -> PrimitiveFunc
threeArgs f = \args -> do
  args' <- tupleToList args
  case args' of 
    [val, val', val''] -> f val val' val'' >>= return . Value
    _ -> throwError $ ArgumentsNumPrimitive 3 $ length args'

--
-- Constants
--

constants :: [(String, EgisonValue)]
constants = [
--              ("pi", Float 3.141592653589793 0)
--             ,("e" , Float 2.718281828459045 0)
              ]

--
-- Primitives
--

primitives :: [(String, PrimitiveFunc)]
primitives = [ ("+", plus)
             , ("-", minus)
             , ("*", multiply)
             , ("/", divide)
             , ("+'", plus)
             , ("-'", minus)
             , ("*'", multiply)
             , ("/'", divide)
             , ("numerator", numerator')
             , ("denominator", denominator')
             , ("from-math-expr", fromScalarExpr)
             , ("to-math-expr", toScalarExpr)
             , ("to-math-expr'", toScalarExpr)
               
             , ("modulo",    integerBinaryOp mod)
             , ("quotient",   integerBinaryOp quot)
             , ("remainder", integerBinaryOp rem)
             , ("abs", rationalUnaryOp abs)
             , ("neg", rationalUnaryOp negate)
               
             , ("eq?",  eq)
             , ("lt?",  lt)
             , ("lte?", lte)
             , ("gt?",  gt)
             , ("gte?", gte)
               
             , ("round",    floatToIntegerOp round)
             , ("floor",    floatToIntegerOp floor)
             , ("ceiling",  floatToIntegerOp ceiling)
             , ("truncate", truncate')
             , ("real-part", realPart)
             , ("imaginary-part", imaginaryPart)
               
             , ("sqrt", floatUnaryOp "sqrt" sqrt)
             , ("sqrt'", floatUnaryOp "sqrt" sqrt)
             , ("exp", floatUnaryOp "exp" exp)
             , ("log", floatUnaryOp "log" log)
             , ("sin", floatUnaryOp "sin" sin)
             , ("cos", floatUnaryOp "cos" cos)
             , ("tan", floatUnaryOp "tan" tan)
             , ("asin", floatUnaryOp "asin" asin)
             , ("acos", floatUnaryOp "acos" acos)
             , ("atan", floatUnaryOp "atan" atan)
             , ("sinh", floatUnaryOp "sinh" sinh)
             , ("cosh", floatUnaryOp "cosh" cosh)
             , ("tanh", floatUnaryOp "tanh" tanh)
             , ("asinh", floatUnaryOp "asinh" asinh)
             , ("acosh", floatUnaryOp "acosh" acosh)
             , ("atanh", floatUnaryOp "atanh" atanh)
               
             , ("itof", integerToFloat)
             , ("rtof", rationalToFloat)
             , ("ctoi", charToInteger)
             , ("itoc", integerToChar)

             , ("pack", pack)
             , ("unpack", unpack)
             , ("uncons-string", unconsString)
             , ("length-string", lengthString)
             , ("append-string", appendString)
             , ("split-string", splitString)
             , ("regex", regexString)
             , ("regex-cg", regexStringCaptureGroup)

             , ("read-process", readProcess')
               
             , ("read", read')
             , ("read-tsv", readTSV)
             , ("show", show')
             , ("show-tsv", showTSV')

             , ("empty?", isEmpty')
             , ("uncons", uncons')
             , ("unsnoc", unsnoc')

             , ("bool?", isBool')
             , ("integer?", isInteger')
             , ("rational?", isRational')
             , ("number?", isNumber')
             , ("float?", isFloat')
             , ("char?", isChar')
             , ("string?", isString')
             , ("collection?", isCollection')
             , ("array?", isArray')
             , ("hash?", isHash')

             , ("assert", assert)
             , ("assert-equal", assertEqual)
             ]

rationalUnaryOp :: (Rational -> Rational) -> PrimitiveFunc
rationalUnaryOp op = oneArg $ \val -> do
  r <- fromEgison val
  let r' =  op r
  return $ toEgison r'
  
rationalBinaryOp :: (Rational -> Rational -> Rational) -> PrimitiveFunc
rationalBinaryOp op = twoArgs $ \val val' -> do
  r <- fromEgison val :: EgisonM Rational
  r' <- fromEgison val' :: EgisonM Rational
  let r'' = (op r r'')
  return $ toEgison r''

rationalBinaryPred :: (Rational -> Rational -> Bool) -> PrimitiveFunc
rationalBinaryPred pred = twoArgs $ \val val' -> do
  r <- fromEgison val
  r' <- fromEgison val'
  return $ Bool $ pred r r'

integerBinaryOp :: (Integer -> Integer -> Integer) -> PrimitiveFunc
integerBinaryOp op = twoArgs $ \val val' -> do
  i <- fromEgison val
  i' <- fromEgison val'
  return $ toEgison (op i i')

integerBinaryPred :: (Integer -> Integer -> Bool) -> PrimitiveFunc
integerBinaryPred pred = twoArgs $ \val val' -> do
  i <- fromEgison val
  i' <- fromEgison val'
  return $ Bool $ pred i i'

floatUnaryOp :: String -> (Double -> Double) -> PrimitiveFunc
floatUnaryOp name op = oneArg $ \val -> do
  case val of
    (Float f 0) -> return $ Float (op f) 0
    (ScalarExpr mExpr) -> return $ ScalarExpr (Div (Plus [(Term 1 [(Apply name [mExpr], 1)])]) (Plus [(Term 1 [])]))
    _ -> throwError $ TypeMismatch "number" (Value val)

floatBinaryOp :: String -> (Double -> Double -> Double) -> PrimitiveFunc
floatBinaryOp name op = twoArgs $ \val val' -> do
  case (val, val') of
    ((Float f 0), (Float f' 0)) -> return $ Float (op f f') 0
    ((ScalarExpr mExpr), (ScalarExpr mExpr')) -> return $ ScalarExpr (Div (Plus [(Term 1 [(Apply name [mExpr, mExpr'], 1)])]) (Plus [(Term 1 [])]))

floatBinaryPred :: (Double -> Double -> Bool) -> PrimitiveFunc
floatBinaryPred pred = twoArgs $ \val val' -> do
  f <- fromEgison val
  f' <- fromEgison val'
  return $ Bool $ pred f f'

--
-- Arith
--

numberBinaryOp :: (ScalarExpr -> ScalarExpr -> ScalarExpr) -> (EgisonValue -> EgisonValue -> EgisonValue) -> PrimitiveFunc
numberBinaryOp mOp fOp args = do
  args' <- tupleToList args
  case args' of 
    [val, val'] -> numberBinaryOp' val val' >>= return . Value
    _ -> throwError $ ArgumentsNumPrimitive 2 $ length args'
 where
  numberBinaryOp' f@(Float _ _) f'@(Float _ _) = return $ fOp f f'
  numberBinaryOp' val           (Float x' y')  = numberBinaryOp' (numberToFloat' val) (Float x' y')
  numberBinaryOp' (Float x y)   val'           = numberBinaryOp' (Float x y) (numberToFloat' val')
  numberBinaryOp' (ScalarExpr m1) (ScalarExpr m2)  = (return . ScalarExpr . mathNormalize') (mOp m1 m2)
  numberBinaryOp' (ScalarExpr _)  val'           = throwError $ TypeMismatch "number" (Value val')
  numberBinaryOp' val           _              = throwError $ TypeMismatch "number" (Value val)


plus :: PrimitiveFunc
plus = numberBinaryOp mathPlus (\(Float x y) (Float x' y') -> Float (x + x')  (y + y'))

minus :: PrimitiveFunc
minus = numberBinaryOp (\m1 m2 -> mathPlus m1 (mathNegate m2)) (\(Float x y) (Float x' y') -> Float (x - x')  (y - y'))

multiply :: PrimitiveFunc
multiply = numberBinaryOp mathMult (\(Float x y) (Float x' y') -> Float (x * x' - y * y')  (x * y' + x' * y))

divide :: PrimitiveFunc
divide = numberBinaryOp (\m1 (Div p1 p2) -> mathMult m1 (Div p2 p1)) (\(Float x y) (Float x' y') -> Float ((x * x' + y * y') / (x' * x' + y' * y')) ((y * x' - x * y') / (x' * x' + y' * y')))

numerator' :: PrimitiveFunc
numerator' =  oneArg $ numerator''
 where
  numerator'' (ScalarExpr m) = return $ ScalarExpr (mathNumerator m)
  numerator'' val = throwError $ TypeMismatch "rational" (Value val)

denominator' :: PrimitiveFunc
denominator' =  oneArg $ denominator''
 where
  denominator'' (ScalarExpr m) = return $ ScalarExpr (mathDenominator m)
  denominator'' val = throwError $ TypeMismatch "rational" (Value val)

fromScalarExpr :: PrimitiveFunc
fromScalarExpr = oneArg $ fromScalarExpr'
 where
  fromScalarExpr' (ScalarExpr m) = return $ mathExprToEgison m
  fromScalarExpr' val = throwError $ TypeMismatch "number" (Value val)

toScalarExpr :: PrimitiveFunc
toScalarExpr = oneArg $ toScalarExpr'
 where
  toScalarExpr' val = egisonToScalarExpr val >>= return . ScalarExpr . mathNormalize'

--
-- Pred
--
eq :: PrimitiveFunc
eq = twoArgs $ \val val' ->
  return $ Bool $ val == val'

lt :: PrimitiveFunc
lt = twoArgs $ \val val' -> numberBinaryPred' val val'
 where
  numberBinaryPred' m@(ScalarExpr _) n@(ScalarExpr _) = do
    r <- fromEgison m :: EgisonM Rational
    r' <- fromEgison n :: EgisonM Rational
    return $ Bool $ (<) r r'
  numberBinaryPred' (Float f 0)  (Float f' 0)  = return $ Bool $ (<) f f'
  numberBinaryPred' (ScalarExpr _) val           = throwError $ TypeMismatch "number" (Value val)
  numberBinaryPred' (Float _ _)  val           = throwError $ TypeMismatch "float" (Value val)
  numberBinaryPred' val          _             = throwError $ TypeMismatch "number" (Value val)
  
lte :: PrimitiveFunc
lte = twoArgs $ \val val' -> numberBinaryPred' val val'
 where
  numberBinaryPred' m@(ScalarExpr _) n@(ScalarExpr _) = do
    r <- fromEgison m :: EgisonM Rational
    r' <- fromEgison n :: EgisonM Rational
    return $ Bool $ (<=) r r'
  numberBinaryPred' (Float f 0)  (Float f' 0)  = return $ Bool $ (<=) f f'
  numberBinaryPred' (ScalarExpr _) val           = throwError $ TypeMismatch "number" (Value val)
  numberBinaryPred' (Float _ _)  val           = throwError $ TypeMismatch "float" (Value val)
  numberBinaryPred' val          _             = throwError $ TypeMismatch "number" (Value val)
  
gt :: PrimitiveFunc
gt = twoArgs $ \val val' -> numberBinaryPred' val val'
 where
  numberBinaryPred' m@(ScalarExpr _) n@(ScalarExpr _) = do
    r <- fromEgison m :: EgisonM Rational
    r' <- fromEgison n :: EgisonM Rational
    return $ Bool $ (>) r r'
  numberBinaryPred' (Float f 0)  (Float f' 0)  = return $ Bool $ (>) f f'
  numberBinaryPred' (ScalarExpr _) val           = throwError $ TypeMismatch "number" (Value val)
  numberBinaryPred' (Float _ _)  val           = throwError $ TypeMismatch "float" (Value val)
  numberBinaryPred' val          _             = throwError $ TypeMismatch "number" (Value val)
  
gte :: PrimitiveFunc
gte = twoArgs $ \val val' -> numberBinaryPred' val val'
 where
  numberBinaryPred' m@(ScalarExpr _) n@(ScalarExpr _) = do
    r <- fromEgison m :: EgisonM Rational
    r' <- fromEgison n :: EgisonM Rational
    return $ Bool $ (>=) r r'
  numberBinaryPred' (Float f 0)    (Float f' 0)  = return $ Bool $ (>=) f f'
  numberBinaryPred' (ScalarExpr _) val           = throwError $ TypeMismatch "number" (Value val)
  numberBinaryPred' (Float _ _)    val           = throwError $ TypeMismatch "float" (Value val)
  numberBinaryPred' val            _             = throwError $ TypeMismatch "number" (Value val)
  
truncate' :: PrimitiveFunc
truncate' = oneArg $ \val -> numberUnaryOp' val
 where
  numberUnaryOp' (ScalarExpr (Div (Plus []) _)) = return $ toEgison (0 :: Integer)
  numberUnaryOp' (ScalarExpr (Div (Plus [(Term x [])]) (Plus [(Term y [])]))) = return $ toEgison (quot x y)
  numberUnaryOp' (Float x _)           = return $ toEgison ((truncate x) :: Integer)
  numberUnaryOp' val                   = throwError $ TypeMismatch "ratinal or float" (Value val)

realPart :: PrimitiveFunc
realPart =  oneArg $ realPart'
 where
  realPart' (Float x y) = return $ Float x 0
  realPart' val = throwError $ TypeMismatch "float" (Value val)

imaginaryPart :: PrimitiveFunc
imaginaryPart =  oneArg $ imaginaryPart'
 where
  realPart' (Float _ y) = return $ Float y 0
  imaginaryPart' val = throwError $ TypeMismatch "float" (Value val)

--
-- Transform
--
numberToFloat' :: EgisonValue -> EgisonValue
numberToFloat' (ScalarExpr (Div (Plus []) _)) = Float 0 0
numberToFloat' (ScalarExpr (Div (Plus [(Term x [])]) (Plus [(Term y [])]))) = Float (fromRational (x % y)) 0

integerToFloat :: PrimitiveFunc
integerToFloat = rationalToFloat

rationalToFloat :: PrimitiveFunc
rationalToFloat = oneArg $ \val ->
  case val of
    (ScalarExpr (Div (Plus []) _)) -> return $ numberToFloat' val
    (ScalarExpr (Div (Plus [(Term _ [])]) (Plus [(Term _ [])]))) -> return $ numberToFloat' val
    _ -> throwError $ TypeMismatch "integer or rational number" (Value val)

charToInteger :: PrimitiveFunc
charToInteger = oneArg $ \val -> do
  case val of
    Char c -> do
      let i = fromIntegral $ ord c :: Integer
      return $ toEgison i
    _ -> throwError $ TypeMismatch "character" (Value val)

integerToChar :: PrimitiveFunc
integerToChar = oneArg $ \val -> do
  case val of
    (ScalarExpr _) -> do
       i <- fromEgison val :: EgisonM Integer
       return $ Char $ chr $ fromIntegral i
    _ -> throwError $ TypeMismatch "integer" (Value val)

floatToIntegerOp :: (Double -> Integer) -> PrimitiveFunc
floatToIntegerOp op = oneArg $ \val -> do
  f <- fromEgison val
  return $ toEgison (op f)

--
-- String
--
pack :: PrimitiveFunc
pack = oneArg $ \val -> do
  str <- packStringValue val
  return $ String str

unpack :: PrimitiveFunc
unpack = oneArg $ \val -> do
  case val of
    String str -> return $ toEgison (T.unpack str)
    _ -> throwError $ TypeMismatch "string" (Value val)

unconsString :: PrimitiveFunc
unconsString = oneArg $ \val -> do
  case val of
    String str -> case T.uncons str of
                    Just (c, rest) ->  return $ Tuple [Char c, String rest]
                    Nothing -> throwError $ Default "Tried to unsnoc empty string"
    _ -> throwError $ TypeMismatch "string" (Value val)

lengthString :: PrimitiveFunc
lengthString = oneArg $ \val -> do
  case val of
    String str -> return . (\x -> toEgison x) . toInteger $ T.length str
    _ -> throwError $ TypeMismatch "string" (Value val)

appendString :: PrimitiveFunc
appendString = twoArgs $ \val1 val2 -> do
  case (val1, val2) of
    (String str1, String str2) -> return . String $ T.append str1 str2
    (String _, _) -> throwError $ TypeMismatch "string" (Value val2)
    (_, _) -> throwError $ TypeMismatch "string" (Value val1)

splitString :: PrimitiveFunc
splitString = twoArgs $ \pat src -> do
  case (pat, src) of
    (String patStr, String srcStr) -> return . Collection . Sq.fromList $ map String $ T.splitOn patStr srcStr
    (String _, _) -> throwError $ TypeMismatch "string" (Value src)
    (_, _) -> throwError $ TypeMismatch "string" (Value pat)

regexString :: PrimitiveFunc
regexString = twoArgs $ \pat src -> do
  case (pat, src) of
    (String patStr, String srcStr) -> do
      let (a, b, c) = (((T.unpack srcStr) =~ (T.unpack patStr)) :: (String, String, String))
      if b == ""
        then return . Collection . Sq.fromList $ []
        else return . Collection . Sq.fromList $ [Tuple [String $ T.pack a, String $ T.pack b, String $ T.pack c]]
    (String _, _) -> throwError $ TypeMismatch "string" (Value src)
    (_, _) -> throwError $ TypeMismatch "string" (Value pat)

regexStringCaptureGroup :: PrimitiveFunc
regexStringCaptureGroup = twoArgs $ \pat src -> do
  case (pat, src) of
    (String patStr, String srcStr) -> do
      let ret = (((T.unpack srcStr) =~ (T.unpack patStr)) :: [[String]])
      case ret of 
        [] -> return . Collection . Sq.fromList $ []
        ((x:xs):_) -> do let (a, c) = T.breakOn (T.pack x) srcStr
                         return . Collection . Sq.fromList $ [Tuple [String a, Collection (Sq.fromList (map (String . T.pack) xs)), String (T.drop (length x) c)]]
    (String _, _) -> throwError $ TypeMismatch "string" (Value src)
    (_, _) -> throwError $ TypeMismatch "string" (Value pat)

--regexStringMatch :: PrimitiveFunc
--regexStringMatch = twoArgs $ \pat src -> do
--  case (pat, src) of
--    (String patStr, String srcStr) -> return . Bool $ (((T.unpack srcStr) =~ (T.unpack patStr)) :: Bool)
--    (String _, _) -> throwError $ TypeMismatch "string" (Value src)
--    (_, _) -> throwError $ TypeMismatch "string" (Value pat)

readProcess' :: PrimitiveFunc
readProcess' = threeArgs $ \cmd args input -> do
  case (cmd, args, input) of
    (String cmdStr, Collection argStrs, String inputStr) -> do
      outputStr <- liftIO $ readProcess (T.unpack cmdStr) (map (\arg -> case arg of
                                                                          String argStr -> T.unpack argStr)
                                                                (toList argStrs)) (T.unpack inputStr)
      return (String (T.pack outputStr))
    (_, _, _) -> throwError $ TypeMismatch "(string, collection, string)" (Value (Tuple [cmd, args, input]))

read' :: PrimitiveFunc
read'= oneArg $ \val -> fromEgison val >>= readExpr . T.unpack >>= evalExprDeep nullEnv

readTSV :: PrimitiveFunc
readTSV= oneArg $ \val -> do rets <- fromEgison val >>= readExprs . T.unpack >>= mapM (evalExprDeep nullEnv)
                             case rets of
                               [ret] -> return ret
                               _ -> return (Tuple rets)

show' :: PrimitiveFunc
show'= oneArg $ \val -> return $ toEgison $ T.pack $ show val

showTSV' :: PrimitiveFunc
showTSV'= oneArg $ \val -> return $ toEgison $ T.pack $ showTSV val

--
-- Collection
--
isEmpty' :: PrimitiveFunc
isEmpty' whnf = do
  b <- isEmptyCollection whnf
  if b
    then return $ Value $ Bool True
    else return $ Value $ Bool False

uncons' :: PrimitiveFunc
uncons' whnf = do
  mRet <- runMaybeT (unconsCollection whnf)
  case mRet of
    Just (carObjRef, cdrObjRef) -> return $ Intermediate $ ITuple [carObjRef, cdrObjRef]
    Nothing -> throwError $ Default $ "cannot uncons collection"

unsnoc' :: PrimitiveFunc
unsnoc' whnf = do
  mRet <- runMaybeT (unsnocCollection whnf)
  case mRet of
    Just (racObjRef, rdcObjRef) -> return $ Intermediate $ ITuple [racObjRef, rdcObjRef]
    Nothing -> throwError $ Default $ "cannot unsnoc collection"

-- Test

assert ::  PrimitiveFunc
assert = twoArgs $ \label test -> do
  test <- fromEgison test
  if test
    then return $ Bool True
    else throwError $ Assertion $ show label

assertEqual :: PrimitiveFunc
assertEqual = threeArgs $ \label actual expected -> do
  if actual == expected
    then return $ Bool True
    else throwError $ Assertion $ show label ++ "\n expected: " ++ show expected ++
                                  "\n but found: " ++ show actual

--
-- IO Primitives
--

ioPrimitives :: [(String, PrimitiveFunc)]
ioPrimitives = [
                 ("return", return')
               , ("open-input-file", makePort ReadMode)
               , ("open-output-file", makePort WriteMode)
               , ("close-input-port", closePort)
               , ("close-output-port", closePort)
               , ("read-char", readChar)
               , ("read-line", readLine)
               , ("write-char", writeChar)
               , ("write", writeString)
                 
               , ("read-char-from-port", readCharFromPort)
               , ("read-line-from-port", readLineFromPort)
               , ("write-char-to-port", writeCharToPort)
               , ("write-to-port", writeStringToPort)
                 
               , ("eof?", isEOFStdin)
               , ("flush", flushStdout)
               , ("eof-port?", isEOFPort)
               , ("flush-port", flushPort)
               , ("read-file", readFile')
                 
               , ("rand", randRange)
--               , ("sqlite", sqlite)
               ]

makeIO :: EgisonM EgisonValue -> EgisonValue
makeIO m = IOFunc $ liftM (Value . Tuple . (World :) . (:[])) m

makeIO' :: EgisonM () -> EgisonValue
makeIO' m = IOFunc $ m >> return (Value $ Tuple [World, Tuple []])

return' :: PrimitiveFunc
return' = oneArg $ \val -> return $ makeIO $ return val

makePort :: IOMode -> PrimitiveFunc
makePort mode = oneArg $ \val -> do
  filename <- fromEgison val
  port <- liftIO $ openFile (T.unpack filename) mode
  return $ makeIO $ return (Port port)

closePort :: PrimitiveFunc
closePort = oneArg $ \val -> do
  port <- fromEgison val
  return $ makeIO' $ liftIO $ hClose port

writeChar :: PrimitiveFunc
writeChar = oneArg $ \val -> do
  c <- fromEgison val
  return $ makeIO' $ liftIO $ putChar c

writeCharToPort :: PrimitiveFunc
writeCharToPort = twoArgs $ \val val' -> do
  port <- fromEgison val
  c <- fromEgison val'
  return $ makeIO' $ liftIO $ hPutChar port c

writeString :: PrimitiveFunc
writeString = oneArg $ \val -> do
  s <- fromEgison val
  return $ makeIO' $ liftIO $ T.putStr s
  
writeStringToPort :: PrimitiveFunc
writeStringToPort = twoArgs $ \val val' -> do
  port <- fromEgison val
  s <- fromEgison val'
  return $ makeIO' $ liftIO $ T.hPutStr port s

flushStdout :: PrimitiveFunc
flushStdout = noArg $ return $ makeIO' $ liftIO $ hFlush stdout

flushPort :: PrimitiveFunc
flushPort = oneArg $ \val -> do
  port <- fromEgison val
  return $ makeIO' $ liftIO $ hFlush port

readChar :: PrimitiveFunc
readChar = noArg $ return $ makeIO $ liftIO $ liftM Char getChar

readCharFromPort :: PrimitiveFunc
readCharFromPort = oneArg $ \val -> do
  port <- fromEgison val
  c <- liftIO $ hGetChar port
  return $ makeIO $ return (Char c)

readLine :: PrimitiveFunc
readLine = noArg $ return $ makeIO $ liftIO $ liftM toEgison T.getLine

readLineFromPort :: PrimitiveFunc
readLineFromPort = oneArg $ \val -> do
  port <- fromEgison val
  s <- liftIO $ T.hGetLine port
  return $ makeIO $ return $ toEgison s

readFile' :: PrimitiveFunc
readFile' =  oneArg $ \val -> do
  filename <- fromEgison val
  s <- liftIO $ T.readFile $ T.unpack filename
  return $ makeIO $ return $ toEgison s
  
isEOFStdin :: PrimitiveFunc
isEOFStdin = noArg $ return $ makeIO $ liftIO $ liftM Bool isEOF

isEOFPort :: PrimitiveFunc
isEOFPort = oneArg $ \val -> do
  port <- fromEgison val
  b <- liftIO $ hIsEOF port
  return $ makeIO $ return (Bool b)

randRange :: PrimitiveFunc
randRange = twoArgs $ \val val' -> do
  i <- fromEgison val :: EgisonM Integer
  i' <- fromEgison val' :: EgisonM Integer
  n <- liftIO $ getStdRandom $ randomR (i, i')
  return $ makeIO $ return $ toEgison n

 {-- -- for 'egison-sqlite'
sqlite :: PrimitiveFunc
sqlite  = twoArgs $ \val val' -> do
  dbName <- fromEgison val
  qStr <- fromEgison val'
  ret <- liftIO $ query' (T.pack dbName) $ T.pack qStr
  return $ makeIO $ return $ Collection $ Sq.fromList $ map (\r -> Tuple (map toEgison r)) ret
 where
  query' :: T.Text -> T.Text -> IO [[String]]
  query' dbName q = do
    db <- SQLite.open dbName
    rowsRef <- newIORef []
    SQLite.execWithCallback db q (\_ _ mcs -> do
                                    row <- forM mcs (\mcol -> case mcol of
                                                              Just col ->  return $ T.unpack col
                                                              Nothing -> return "null")
                                    rows <- readIORef rowsRef
                                    writeIORef rowsRef (row:rows))
    SQLite.close db
    ret <- readIORef rowsRef
    return $ reverse ret
 --} -- for 'egison-sqlite'
