require "base64"
require "digest"
require "fileutils"
require "json"
require "openssl"

# The RS256 keypair that signs every test token. It lives in the harness's top-level keys/ folder
# (mounted at /keys in Docker), created on first use:
#
#   keys/signing-key.pem   private key (gitignored)
#   keys/jwks.json         the PUBLIC key as a JWKS: copy this into the PowerSync instance's client
#                          auth and the write API's verifier (see keys/README.md)
#
# The kid is the RFC 7638 thumbprint of the public key, so it is stable for a given key.
class SigningKey
  attr_reader :private_key, :kid

  def initialize(private_key)
    @private_key = private_key
    @kid = self.class.thumbprint(public_components)
  end

  def public_jwk
    public_components.merge("kid" => kid, "alg" => "RS256", "use" => "sig")
  end

  def jwks = { "keys" => [public_jwk] }

  class << self
    def dir = File.expand_path(ENV["KEYS_DIR"].presence || "../keys", Rails.root)
    def pem_path = File.join(dir, "signing-key.pem")
    def jwks_path = File.join(dir, "jwks.json")

    # Loads the key, creating it (and jwks.json) if missing. Returns [key, created].
    def load_or_create
      created = !File.file?(pem_path)
      if created
        FileUtils.mkdir_p(dir)
        File.write(pem_path, OpenSSL::PKey::RSA.generate(2048).to_pem, perm: 0o600)
      end
      key = new(OpenSSL::PKey::RSA.new(File.read(pem_path)))
      write_jwks(key)
      [key, created]
    end

    def current = (@current ||= load_or_create.first)

    # A throwaway key under the real kid, for the wrong-key token test: the verifier finds a key
    # and fails on the signature itself.
    def rogue
      @rogue ||= new(OpenSSL::PKey::RSA.generate(2048)).tap { |key| key.instance_variable_set(:@kid, current.kid) }
    end

    def thumbprint(components)
      canonical = JSON.generate({ "e" => components["e"], "kty" => components["kty"], "n" => components["n"] })
      b64url(Digest::SHA256.digest(canonical))
    end

    def b64url(bytes) = Base64.urlsafe_encode64(bytes, padding: false)

    private

    def write_jwks(key)
      body = JSON.pretty_generate(key.jwks) + "\n"
      File.write(jwks_path, body) unless File.file?(jwks_path) && File.read(jwks_path) == body
    end
  end

  private

  def public_components
    @public_components ||= {
      "kty" => "RSA",
      "n" => self.class.b64url(private_key.n.to_s(2)),
      "e" => self.class.b64url(private_key.e.to_s(2))
    }
  end
end
