{-# LANGUAGE LambdaCase  #-}
{-# LANGUAGE Trustworthy #-}
--------------------------------------------------------------------
-- |
-- Module    : Data.MessagePack.Put
-- Copyright : (c) Hideyuki Tanaka, 2009-2015
-- License   : BSD3
--
-- Maintainer:  tanaka.hideyuki@gmail.com
-- Stability :  experimental
-- Portability: portable
--
-- MessagePack Serializer using @Data.Binary@
--
--------------------------------------------------------------------

module Data.MessagePack.Put
  ( putObject
  , putNil
  , putBool
  , putInt
  , putWord
  , putFloat
  , putDouble
  , putStr
  , putBin
  , putArray
  , putMap
  , putExt
  ) where

import           Data.Binary            (Put)
import           Data.Binary.IEEE754    (putFloat32be, putFloat64be)
import           Data.Binary.Put        (putByteString, putWord16be,
                                         putWord32be, putWord64be, putWord8,
                                         putWord8)
import           Data.Bits              ((.|.))
import qualified Data.ByteString        as S
import           Data.Int               (Int64)
import qualified Data.Text              as T
import qualified Data.Text.Encoding     as T
import           Data.Word              (Word64, Word8)

import           Prelude                hiding (putStr)

import           Data.MessagePack.Types (Object (..))


putObject :: Object -> Put
putObject = \case
  ObjectNil      -> putNil
  ObjectBool   b -> putBool b
  ObjectInt    n -> putInt n
  ObjectWord   n -> putWord n
  ObjectFloat  f -> putFloat f
  ObjectDouble d -> putDouble d
  ObjectStr    t -> putStr t
  ObjectBin    b -> putBin b
  ObjectArray  a -> putArray putObject a
  ObjectMap    m -> putMap putObject putObject m
  ObjectExt  b r -> putExt b r

putNil :: Put
putNil = putWord8 0xC0

putBool :: Bool -> Put
putBool False = putWord8 0xC2
putBool True  = putWord8 0xC3

putInt :: Int64 -> Put
putInt n
  | -0x20 <= n && n < 0x80 =
                     putWord8     (fromIntegral n)
  | 0     <= n && n < 0x100 =
    putWord8 0xCC >> putWord8     (fromIntegral n)
  | 0     <= n && n < 0x10000 =
    putWord8 0xCD >> putWord16be  (fromIntegral n)
  | 0     <= n && n < 0x100000000 =
    putWord8 0xCE >> putWord32be  (fromIntegral n)
  | 0     <= n =
    putWord8 0xCF >> putWord64be  (fromIntegral n)
  | -0x80 <= n =
    putWord8 0xD0 >> putWord8     (fromIntegral n)
  | -0x8000 <= n =
    putWord8 0xD1 >> putWord16be  (fromIntegral n)
  | -0x80000000 <= n =
    putWord8 0xD2 >> putWord32be  (fromIntegral n)
  | otherwise =
    putWord8 0xD3 >> putWord64be (fromIntegral n)

putWord :: Word64 -> Put
putWord n
  | n < 0x80 =
                     putWord8     (fromIntegral n)
  | n < 0x100 =
    putWord8 0xCC >> putWord8     (fromIntegral n)
  | n < 0x10000 =
    putWord8 0xCD >> putWord16be  (fromIntegral n)
  | n < 0x100000000 =
    putWord8 0xCE >> putWord32be  (fromIntegral n)
  | otherwise =
    putWord8 0xCF >> putWord64be  n

putFloat :: Float -> Put
putFloat f = do
  putWord8 0xCA
  putFloat32be f

putDouble :: Double -> Put
putDouble d = do
  putWord8 0xCB
  putFloat64be d

putStr :: S.ByteString -> Put
putStr bs = do
  case S.length bs of
    len | len <= 31 ->
          putWord8 $ 0xA0 .|. fromIntegral len
        | len < 0x100 ->
          putWord8 0xD9 >> putWord8    (fromIntegral len)
        | len < 0x10000 ->
          putWord8 0xDA >> putWord16be (fromIntegral len)
        | otherwise ->
          putWord8 0xDB >> putWord32be (fromIntegral len)
  putByteString bs

putBin :: S.ByteString -> Put
putBin bs = do
  case S.length bs of
    len | len < 0x100 ->
          putWord8 0xC4 >> putWord8    (fromIntegral len)
        | len < 0x10000 ->
          putWord8 0xC5 >> putWord16be (fromIntegral len)
        | otherwise ->
          putWord8 0xC6 >> putWord32be (fromIntegral len)
  putByteString bs

putArray :: (a -> Put) -> [a] -> Put
putArray p xs = do
  case length xs of
    len | len <= 15 ->
          putWord8 $ 0x90 .|. fromIntegral len
        | len < 0x10000 ->
          putWord8 0xDC >> putWord16be (fromIntegral len)
        | otherwise ->
          putWord8 0xDD >> putWord32be (fromIntegral len)
  mapM_ p xs

putMap :: (a -> Put) -> (b -> Put) -> [(a, b)] -> Put
putMap p q xs = do
  case length xs of
    len | len <= 15 ->
          putWord8 $ 0x80 .|. fromIntegral len
        | len < 0x10000 ->
          putWord8 0xDE >> putWord16be (fromIntegral len)
        | otherwise ->
          putWord8 0xDF >> putWord32be (fromIntegral len)
  mapM_ (\(a, b) -> p a >> q b) xs

putExt :: Word8 -> S.ByteString -> Put
putExt typ dat = do
  case S.length dat of
    1  -> putWord8 0xD4
    2  -> putWord8 0xD5
    4  -> putWord8 0xD6
    8  -> putWord8 0xD7
    16 -> putWord8 0xD8
    len | len < 0x100   -> putWord8 0xC7 >> putWord8    (fromIntegral len)
        | len < 0x10000 -> putWord8 0xC8 >> putWord16be (fromIntegral len)
        | otherwise     -> putWord8 0xC9 >> putWord32be (fromIntegral len)
  putWord8 typ
  putByteString dat
