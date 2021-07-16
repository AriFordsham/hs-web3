{-# LANGUAGE TypeFamilies #-}

-- |
-- Module      :  Network.Polkadot.Crypto
-- Copyright   :  Aleksandr Krupenkin 2016-2021
-- License     :  Apache-2.0
--
-- Maintainer  :  mail@akru.me
-- Stability   :  experimental
-- Portability :  portable
--
-- Polkadot signing types and methods.
--

module Network.Polkadot.Crypto
  ( Pair(..)
  , MultiPair(multi_address, multi_signer, multi_signature)
  , Ed25519
  , Ecdsa
  ) where

import qualified Crypto.Ecdsa.Signature      as Ecdsa (pack, sign)
import           Crypto.Ecdsa.Utils          (exportPubKey)
import qualified Crypto.PubKey.ECC.ECDSA     as Ecdsa (PrivateKey (..),
                                                       PublicKey (..))
import qualified Crypto.PubKey.ECC.Generate  as Ecdsa (generate)
import           Crypto.PubKey.ECC.Types     (CurveName (SEC_p256k1),
                                              getCurveByName)
import qualified Crypto.PubKey.Ed25519       as Ed25519 (PublicKey, SecretKey,
                                                         generateSecretKey,
                                                         sign, toPublic)
import           Data.BigNum                 (H256, H512, h256, h512)
import           Data.ByteArray              (ByteArrayAccess)
import           Data.ByteString             (ByteString)
import qualified Data.ByteString             as BS (last, take)
import           Data.Maybe                  (fromJust)
import           Data.Proxy                  (Proxy (..))
import           Data.Text                   (Text)
import           Data.Word                   (Word8)

import           Network.Polkadot.Account    (into_account)
import qualified Network.Polkadot.Primitives as P (MultiAddress (..),
                                                   MultiSignature (..),
                                                   MultiSigner (..))

-- | Class suitable for typical cryptographic PKI key pair type.
class Pair a where
    -- | The type which is used to encode a public key.
    type PublicKey a
    -- | The type used to represent a signature. Can be created from a key pair and a message
    -- and verified with the message and a public key.
    type Signature a
    -- | Generate new secure (random) key pair.
    generate :: IO a
    -- | Generate new key pair from the provided `seed`.
    from_seed :: ByteArrayAccess ba => ba -> a
    -- | Generate key pair from given recovery phrase and password.
    from_phrase :: Text -> Maybe Text -> Either String a
    -- | Get a public key.
    public :: a -> PublicKey a
    -- | Sign a message.
    sign :: ByteArrayAccess ba => a -> ba -> Signature a

-- | Multiple cryptographic type support.
class Pair a => MultiPair a where
    -- | Universal short representation of signer account.
    type MultiAddress a
    -- | Universal signer account identifier.
    type MultiSigner a
    -- | Universal signature representation.
    type MultiSignature a
    -- | Derive universal account address.
    multi_address :: Proxy a -> PublicKey a -> MultiAddress a
    -- | Derive universal signer account identifier.
    multi_signer :: Proxy a -> PublicKey a -> MultiSigner a
    -- | Derive universal signature.
    multi_signature :: Proxy a -> Signature a -> MultiSignature a

-- | Ed25519 cryptographic pair.
data Ed25519 = Ed25519 !Ed25519.PublicKey !Ed25519.SecretKey
  deriving Eq

instance Show Ed25519 where
    show = ("Ed25519 " ++) . show . public

instance Pair Ed25519 where
    type PublicKey Ed25519 = H256
    type Signature Ed25519 = H512
    generate = do
        sec <- Ed25519.generateSecretKey
        return $ Ed25519 (Ed25519.toPublic sec) sec
    from_seed = undefined
    from_phrase = undefined
    public (Ed25519 pub _) = fromJust $ h256 pub
    sign (Ed25519 pub sec) input = ed25519_sign sec pub input

-- | ECDSA cryptographic pair.
data Ecdsa = Ecdsa !Ecdsa.PublicKey !Ecdsa.PrivateKey
  deriving Eq

instance Show Ecdsa where
    show = ("Ecdsa " ++) . show . public

instance Pair Ecdsa where
    type PublicKey Ecdsa = H512
    type Signature Ecdsa = (H512, Word8)
    generate = uncurry Ecdsa <$> Ecdsa.generate (getCurveByName SEC_p256k1)
    from_seed = undefined
    from_phrase = undefined
    public (Ecdsa pub _) = fromJust $ h512 (exportPubKey pub :: ByteString)
    sign (Ecdsa _ sec) input = ecdsa_sign sec input

ed25519_sign :: ByteArrayAccess a => Ed25519.SecretKey -> Ed25519.PublicKey -> a -> H512
ed25519_sign sec pub = fromJust . h512 . Ed25519.sign sec pub

ecdsa_sign :: ByteArrayAccess a => Ecdsa.PrivateKey -> a -> (H512, Word8)
ecdsa_sign sec input = (fromJust $ h512 $ BS.take 64 rsv, BS.last rsv)
  where
    rsv = Ecdsa.pack (Ecdsa.sign sec input)

instance MultiPair Ed25519 where
    type MultiSigner Ed25519 = P.MultiSigner
    type MultiAddress Ed25519 = P.MultiAddress
    type MultiSignature Ed25519 = P.MultiSignature
    multi_signer _ = P.Ed25519Signer
    multi_address _ = P.MaId . into_account . multi_signer (Proxy :: Proxy Ed25519)
    multi_signature _ = P.Ed25519Signature

instance MultiPair Ecdsa where
    type MultiSigner Ecdsa = P.MultiSigner
    type MultiAddress Ecdsa = P.MultiAddress
    type MultiSignature Ecdsa = P.MultiSignature
    multi_signer _ = P.EcdsaSigner
    multi_address _ = P.MaId . into_account . multi_signer (Proxy :: Proxy Ecdsa)
    multi_signature _ = uncurry P.EcdsaSignature
