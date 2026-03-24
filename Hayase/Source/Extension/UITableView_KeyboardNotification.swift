//
//  UITableView_KeyboardNotification.swift
//  Assignment4
//
//  Created by Charles Augustine on 7/10/15.
//

import UIKit

extension UITableView {
    func adjustInsetsForWillShowKeyboardNotification(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let rectValue = (userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue,
              let convertedRect = self.superview?.convert(rectValue, from: nil),
              let animationDuration = (userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue else { return }
        UIView.animate(withDuration: animationDuration) {
            var contentInset = self.contentInset
            contentInset.bottom = convertedRect.height
            self.contentInset = contentInset
            self.scrollIndicatorInsets = contentInset
        }
    }

    func adjustInsetsForWillHideKeyboardNotification(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let animationDuration = (userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue else { return }
        UIView.animate(withDuration: animationDuration) {
            var contentInset = self.contentInset
            contentInset.bottom = 0.0
            self.contentInset = contentInset
            self.scrollIndicatorInsets = contentInset
        }
    }
}
