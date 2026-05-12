import SwiftUI

@MainActor
public struct GestureLockVerifyView: View {
    public enum Purpose {
        case disable
        case unlock
    }

    let username: String
    let purpose: Purpose
    let completion: (Bool) -> Void
    
    @Environment(\.gestureLockStore) private var store
    @State private var path: [Int] = []
    @State private var isError = false
    @State private var message = "请绘制手势密码"

    @EnvironmentObject private var session: AuthSession

    public var body: some View {
        NavigationStack {
            VStack {
                Spacer()
                Text(message)
                    .font(.headline)
                    .foregroundColor(isError ? .red : .primary)
                
                GestureLockGrid(path: $path, isError: $isError)
                
                Spacer()
            }
            .navigationTitle(purpose == .disable ? "验证手势密码" : "解锁闪记")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if purpose == .disable {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { completion(false) }
                    }
                } else {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("忘记密码") {
                            // D2-I6-17 忘记手势触发登出回登录
                            session.signOut()
                            GestureLockManager.shared.unlock()
                        }
                        .foregroundColor(.red)
                    }
                }
            }
        }
        .gesture(DragGesture(minimumDistance: 0).onEnded { _ in
            guard path.count > 0 else { return }
            let password = path.map { String($0) }.joined()
            
            if store.verify(password: password, for: username) {
                completion(true)
            } else {
                isError = true
                message = "手势密码错误，请重试"
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    path = []
                    isError = false
                    message = "请绘制手势密码"
                }
            }
        })
    }
}
