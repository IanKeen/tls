import COpenSSL

/**
    An SSL Socket.
*/
public final class Socket {
    public typealias CSSL = UnsafeMutablePointer<ssl_st>

    public let cSSL: CSSL
    public let context: Context

    /**
        Creates a Socket from an SSL context and an
        unsecured socket's file descriptor.

        - parameter context: Re-usable SSL.Context in either Client or Server mode
        - parameter descriptor: The file descriptor from an unsecure socket already created.
    */
    public init(context: Context, descriptor: Int32) throws {
        guard let ssl = SSL_new(context.cContext) else {
            throw Error.socketCreation(error)
        }

        SSL_set_fd(ssl, descriptor)

        self.context = context
        self.cSSL = ssl
    }

    deinit {
        SSL_shutdown(cSSL)
        SSL_free(cSSL)
    }

    /**
        Connects to an SSL server from this client.

        This should only be called if the Context's mode is `.client`
    */
    public func connect() throws {
        let result = SSL_connect(cSSL)
        guard result == Result.OK else {
            throw Error.connect(SocketError(result), error)
        }
    }

    /**
        Accepts a connection to this SSL server from a client.

        This should only be called if the Context's mode is `.server`
    */
    public func accept() throws {
        let result = SSL_accept(cSSL)
        guard result == Result.OK else {
            throw Error.accept(SocketError(result), error)
        }
    }

    /**
        Receives bytes from the secure socket.

        - parameter max: The maximum amount of bytes to receive.
    */
    public func receive(max: Int) throws -> [UInt8]  {
        let pointer = UnsafeMutablePointer<UInt8>.init(allocatingCapacity: max)
        defer {
            pointer.deallocateCapacity(max)
        }

        let result = SSL_read(cSSL, pointer, max.int32)
        let bytesRead = Int(result)

        guard bytesRead >= 0 else {
            throw Error.receive(SocketError(result), error)
        }


        let buffer = UnsafeBufferPointer<UInt8>.init(start: pointer, count: bytesRead)
        return Array(buffer)
    }

    /**
        Sends bytes to the secure socket.

        - parameter bytes: An array of bytes to send.
    */
    public func send(_ bytes: [UInt8]) throws {
        let buffer = UnsafeBufferPointer<UInt8>(start: bytes, count: bytes.count)

        let bytesSent = SSL_write(cSSL, buffer.baseAddress, bytes.count.int32)

        guard bytesSent >= 0 else {
            throw Error.send(SocketError(bytesSent), error)
        }
    }

    /**
        Verifies the connection with the peer.
     
        - throws: Error.invalidPeerCertificate(PeerCertificateError)
    */
    public func verifyConnection() throws {
        if case .server = context.mode where context.certificates.areSelfSigned {
            return
        }

        guard let certificate = SSL_get_peer_certificate(cSSL) else {
            throw Error.invalidPeerCertificate(.notPresented)
        }
        defer {
            X509_free(certificate)
        }

        let result = SSL_get_verify_result(cSSL).int32
        switch result {
        case X509_V_OK:
            break
        case X509_V_ERR_UNABLE_TO_GET_ISSUER_CERT, X509_V_ERR_UNABLE_TO_GET_ISSUER_CERT_LOCALLY:
            if !context.certificates.areSelfSigned {
                throw Error.invalidPeerCertificate(.noIssuerCertificate)
            }
        default:
            throw Error.invalidPeerCertificate(.invalid)
        }
    }
}
