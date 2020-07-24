{-# LANGUAGE LambdaCase  #-}
{-# LANGUAGE Trustworthy #-}

--------------------------------------------------------------------
-- |
-- Module    : Data.MessagePack.Get
-- Copyright : (c) Hideyuki Tanaka, 2009-2015
-- License   : BSD3
--
-- Maintainer:  tanaka.hideyuki@gmail.com
-- Stability :  experimental
-- Portability: portable
--
-- MessagePack Deserializer using @Data.Binary@
--
--------------------------------------------------------------------

module Data.MessagePack.Get
  ( getObject
  , getNil
  , getBool
  , getInt
  , getWord
  , getFloat
  , getDouble
  , getStr
  , getBin
  , getArray
  , getMap
  , getExt
  ) where

import           Control.Applicative    (empty, (<$), (<$>), (<*>), (<|>))
import           Control.Monad          (guard, replicateM)
import           Data.Binary            (Get)
import           Data.Binary.Get        (getByteString, getWord16be,
                                         getWord32be, getWord64be, getWord8)
import           Data.Binary.IEEE754    (getFloat32be, getFloat64be)
import           Data.Bits              ((.&.))
import qualified Data.ByteString        as S
import           Data.Int               (Int16, Int32, Int64, Int8)
import qualified Data.Text              as T
import qualified Data.Text.Encoding     as T
import           Data.Word              (Word64, Word8)

import           Data.MessagePack.Types (Object (..))

getObject :: Get Object
getObject =
      ObjectNil    <$  getNil
  <|> ObjectBool   <$> getBool
  <|> ObjectInt    <$> getInt
  <|> ObjectWord   <$> getWord
  <|> ObjectFloat  <$> getFloat
  <|> ObjectDouble <$> getDouble
  <|> ObjectStr    <$> getStr
  <|> ObjectBin    <$> getBin
  <|> ObjectArray  <$> getArray getObject
  <|> ObjectMap    <$> getMap getObject getObject
  <|> uncurry ObjectExt <$> getExt

getNil :: Get ()
getNil = tag 0xC0

getBool :: Get Bool
getBool =
  False <$ tag 0xC2 <|>
  True  <$ tag 0xC3

getInt :: Get Int64
getInt =
  getWord8 >>= \case
    c | c .&. 0xE0 == 0xE0 ->
        return $ fromIntegral (fromIntegral c :: Int8)
    0xD0 -> fromIntegral <$> getInt8
    0xD1 -> fromIntegral <$> getInt16be
    0xD2 -> fromIntegral <$> getInt32be
    0xD3 -> fromIntegral <$> getInt64be
    _    -> empty

getWord :: Get Word64
getWord =
  getWord8 >>= \case
    c | c .&. 0x80 == 0x00 ->
        return $ fromIntegral c
    0xCC -> fromIntegral <$> getWord8
    0xCD -> fromIntegral <$> getWord16be
    0xCE -> fromIntegral <$> getWord32be
    0xCF -> fromIntegral <$> getWord64be
    _    -> empty

getFloat :: Get Float
getFloat = tag 0xCA >> getFloat32be

getDouble :: Get Double
getDouble = tag 0xCB >> getFloat64be

getStr :: Get S.ByteString
getStr = do
  len <- getWord8 >>= \case
    t | t .&. 0xE0 == 0xA0 ->
      return $ fromIntegral $ t .&. 0x1F
    0xD9 -> fromIntegral <$> getWord8
    0xDA -> fromIntegral <$> getWord16be
    0xDB -> fromIntegral <$> getWord32be
    _    -> empty
  getByteString len

getBin :: Get S.ByteString
getBin = do
  len <- getWord8 >>= \case
    0xC4 -> fromIntegral <$> getWord8
    0xC5 -> fromIntegral <$> getWord16be
    0xC6 -> fromIntegral <$> getWord32be
    _    -> empty
  getByteString len

getArray :: Get a -> Get [a]
getArray g = do
  len <- getWord8 >>= \case
    t | t .&. 0xF0 == 0x90 ->
      return $ fromIntegral $ t .&. 0x0F
    0xDC -> fromIntegral <$> getWord16be
    0xDD -> fromIntegral <$> getWord32be
    _    -> empty
  replicateM len g

getMap :: Get a -> Get b -> Get [(a, b)]
getMap k v = do
  len <- getWord8 >>= \case
    t | t .&. 0xF0 == 0x80 ->
      return $ fromIntegral $ t .&. 0x0F
    0xDE -> fromIntegral <$> getWord16be
    0xDF -> fromIntegral <$> getWord32be
    _    -> empty
  replicateM len $ (,) <$> k <*> v

getExt :: Get (Word8, S.ByteString)
getExt = do
  len <- getWord8 >>= \case
    0xD4 -> return 1
    0xD5 -> return 2
    0xD6 -> return 4
    0xD7 -> return 8
    0xD8 -> return 16
    0xC7 -> fromIntegral <$> getWord8
    0xC8 -> fromIntegral <$> getWord16be
    0xC9 -> fromIntegral <$> getWord32be
    _    -> empty
  (,) <$> getWord8 <*> getByteString len

getInt8 :: Get Int8
getInt8 = fromIntegral <$> getWord8

getInt16be :: Get Int16
getInt16be = fromIntegral <$> getWord16be

getInt32be :: Get Int32
getInt32be = fromIntegral <$> getWord32be

getInt64be :: Get Int64
getInt64be = fromIntegral <$> getWord64be

tag :: Word8 -> Get ()
tag t = do
  b <- getWord8
  guard $ t == b
