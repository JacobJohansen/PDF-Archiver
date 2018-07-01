//
//  IAPHelper.swift
//  PDFArchiver
//
//  Created by Julian Kahnert on 22.06.18.
//  Copyright © 2018 Julian Kahnert. All rights reserved.
//  The structure is base on: https://www.raywenderlich.com/122144/in-app-purchase-tutorial
//

import StoreKit
import os.log

protocol IAPHelperDelegate: class {
    func updateGUI()
}

class IAPHelper: NSObject {
    fileprivate let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "IAPHelper")
    fileprivate let productIdentifiers: Set<String>
    fileprivate var productsRequest: SKProductsRequest
    fileprivate var receiptRequest = SKReceiptRefreshRequest()

    var products = [SKProduct]()
    var receipt: ParsedReceipt?
    var requestRunning: Int = 0
    weak var delegate: IAPHelperDelegate?

    override init() {
        self.productIdentifiers = Set(["DONATION_LEVEL1", "DONATION_LEVEL2", "DONATION_LEVEL3",
                                       "SUBSCRIPTION_MONTHLY", "SUBSCRIPTION_YEARLY"])
        self.productsRequest = SKProductsRequest(productIdentifiers: self.productIdentifiers)

        // initialize the superclass and add class to payment queue
        super.init()

        // set delegates
        self.productsRequest.delegate = self
        self.receiptRequest.delegate = self
        SKPaymentQueue.default().add(self)

        // request products and receipt
        self.requestProducts()
        self.requestReceipt()
    }

}

// MARK: - StoreKit API

extension IAPHelper {

    public func buyProduct(_ product: SKProduct) {
        os_log("Buying %@ ...", log: self.log, type: .info, product.productIdentifier)
        self.requestStarted()
        let payment = SKPayment(product: product)
        SKPaymentQueue.default().add(payment)
    }

    public func buyProduct(_ productIdentifier: String) {
        for product in self.products where product.productIdentifier == productIdentifier {
            self.buyProduct(product)
            break
        }
    }

    public func requestProducts() {
        self.productsRequest.cancel()
        self.requestStarted()
        self.productsRequest.start()
    }

    public func appUsagePermitted() -> Bool {
        guard let receipt = self.receipt,
              let originalAppVersion = receipt.originalAppVersion else { return false }

        // test if the user has bought the app before the subscription model started
        if originalAppVersion == "1.0" ||
            originalAppVersion.hasPrefix("1.1.") ||
            originalAppVersion.hasPrefix("1.2.") {
            return true
        }

        // test if the user is in a valid subscription
        for receipt in (self.receipt?.inAppPurchaseReceipts)! {

            if let productIdentifier = receipt.productIdentifier,
                productIdentifier.hasPrefix("SUBSCRIPTION_"),
                let subscriptionExpirationDate = receipt.subscriptionExpirationDate,
                subscriptionExpirationDate > Date() {

                // assume that there is a subscription with a valid expiration date
                return true
            }
        }

        return false
    }

    fileprivate func validateReceipt() {
        // validate the receipt data
        let receiptValidator = ReceiptValidator()
        let validationResult = receiptValidator.validateReceipt()

        // handle the validation result
        switch validationResult {
        case .success(let receipt):
            os_log("Receipt validation: successful.", log: self.log, type: .info)
            self.receipt = receipt

        case .error(let error):
            os_log("Receipt validation: unsuccessful (%@)", log: self.log, type: .error, error.localizedDescription)
        }
    }

    fileprivate func requestReceipt(forceRefresh: Bool = false) {
        // refresh receipt if not reachable
        if let receiptUrl = Bundle.main.appStoreReceiptURL,
            let isReachable = try? receiptUrl.checkResourceIsReachable(),
            isReachable,
            forceRefresh == false {
            os_log("Receipt already found, skipping receipt refresh (isReachable: %@, forceRefresh: %@).", log: self.log, type: .info, isReachable, forceRefresh)
            self.validateReceipt()

        } else {
            os_log("Receipt not found, refreshing receipt.", log: self.log, type: .info)
            self.receiptRequest.cancel()
            self.requestStarted()
            self.receiptRequest.start()
        }
    }
}

// MARK: - SKProductsRequestDelegate

extension IAPHelper: SKProductsRequestDelegate {

    internal func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
        self.products = response.products
        os_log("Loaded list of products...", log: self.log, type: .debug)

        // fire up a notification to update the GUI
        self.delegate?.updateGUI()

        // log the products
        for product in self.products {
            os_log("Found product: %@ - %@ - %@", log: self.log, type: .debug, product.productIdentifier, product.localizedTitle, product.localizedPrice)
        }
    }

    internal func request(_ request: SKRequest, didFailWithError error: Error) {
        self.requestStopped()
        os_log("Product Request errored: %@", log: self.log, type: .error, error.localizedDescription)
    }
}

// MARK: - SKPaymentTransactionObserver

extension IAPHelper: SKPaymentTransactionObserver {

    internal func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        for transaction in transactions {
            switch transaction.transactionState {
            case .purchased:
                os_log("Payment completed.", log: self.log, type: .debug)
                SKPaymentQueue.default().finishTransaction(transaction)

                // request a new receipt
                self.validateReceipt()

                // fire up a request finished notification
                self.requestStopped()

                // show thanks message
                DispatchQueue.main.async {
                    dialogOK(messageKey: "payment_complete", infoKey: "payment_thanks", style: .informational)
                }
            case .failed:
                os_log("Payment failed.", log: self.log, type: .debug)
            case .restored:
                os_log("Payment restored.", log: self.log, type: .debug)
            case .deferred:
                os_log("Payment deferred.", log: self.log, type: .debug)
            case .purchasing:
                os_log("In purchasing process.", log: self.log, type: .debug)
            }
        }
    }
}

// MARK: - SKRequestDelegate

extension IAPHelper: SKRequestDelegate {

    internal func requestDidFinish(_ request: SKRequest) {
        self.requestStopped()

        if request is SKReceiptRefreshRequest {
            // validate and save the receipt
            self.validateReceipt()
        }
    }
}

// MARK: - SKRequestDelegate

extension IAPHelper {
    fileprivate func requestStarted() {
        self.requestRunning += 1
        self.delegate?.updateGUI()
    }

    fileprivate func requestStopped() {
        self.requestRunning -= 1
        self.delegate?.updateGUI()
    }
}
