import SwiftUI

@MainActor
public struct GestureLockSetupView: View {
    let username: String
    let completion: (Bool, String?) -> Void
    
    @Environment(\.gestureLockStore) private var store
    @State private var path: [Int] = []
    @State private var isError = false
    @State private var step = 0 // 0: 绘制, 1: 确认
    @State private var firstPassword = ""
    @State private var message = "请绘制手势密码"

    public var body: some View {
        NavigationStack {
            VStack {
                Spacer()
                Text(message)
                    .font(.headline)
                    .foregroundColor(isError ? .red : .primary)
                
                GestureLockGrid(path: $path, isError: $isError)
                    .onChange(of: path) { _ in
                        if isError {
                            isError = false
                            message = step == 0 ? "请绘制手势密码" : "请再次绘制确认"
                        }
                    }
                
                Spacer()
            }
            .navigationTitle(step == 0 ? "设置手势密码" : "确认手势密码")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { completion(false, nil) }
                }
            }
        }
        .gesture(DragGesture(minimumDistance: 0).onEnded { _ in
            guard path.count > 0 else { return }
            if path.count < 4 {
                isError = true
                message = "至少需要连接 4 个点，请重试"
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    path = []
                    isError = false
                    message = step == 0 ? "请绘制手势密码" : "请再次绘制确认"
                }
                return
            }
            
            let currentPassword = path.map { String($0) }.joined()
            if step == 0 {
                firstPassword = currentPassword
                step = 1
                path = []
                message = "请再次绘制确认"
            } else {
                if currentPassword == firstPassword {
                    store.set(password: currentPassword, for: username)
                    completion(true, currentPassword)
                } else {
                    isError = true
                    message = "两次绘制不一致，请重试"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        path = []
                        isError = false
                        message = "请再次绘制确认"
                    }
                }
            }
        })
    }
}
