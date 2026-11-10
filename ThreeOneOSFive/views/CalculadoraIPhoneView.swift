import SwiftUI

struct CalculadoraIPhoneView: View {
    let onContinue: () -> Void

    @State private var display: String = "0"
    @State private var num1: Double = 0
    @State private var num2: Double = 0
    @State private var currentOp: ((Double, Double) -> Double)? = nil
    @State private var waitingForSecond = false
    @State private var lastWasEquals = false

    private let darkGray = Color(red: 0.376, green: 0.376, blue: 0.376) // #606060
    private let lightGray = Color(red: 0.8, green: 0.8, blue: 0.8)     // #ccc
    private let orangeOp = Color.orange

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 12) {
                // Header com botão Entrar (igual o relógio tinha)
                HStack {
                    Spacer()
                    Button(action: onContinue) {
                        HStack(spacing: 6) {
                            Text("Entrar")
                                .font(.system(size: 14, weight: .semibold))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.white.opacity(0.15)))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                // Display
                Text(display)
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)

                // Botões
                VStack(spacing: 12) {
                    // Linha 1: AC  +/-  %  ÷
                    HStack(spacing: 12) {
                        calcButton("AC", bg: lightGray, fg: .black) { limpar() }
                        calcButton("+/-", bg: lightGray, fg: .black) { numeroNegativo() }
                        calcButton("%", bg: lightGray, fg: .black) { porcentagem() }
                        calcButton("÷", bg: orangeOp, fg: .white) { definirOperacao(/) }
                    }

                    // Linha 2: 7 8 9 ×
                    HStack(spacing: 12) {
                        calcButton("7", bg: darkGray, fg: .white) { pegarNum("7") }
                        calcButton("8", bg: darkGray, fg: .white) { pegarNum("8") }
                        calcButton("9", bg: darkGray, fg: .white) { pegarNum("9") }
                        calcButton("×", bg: orangeOp, fg: .white) { definirOperacao(*) }
                    }

                    // Linha 3: 4 5 6 -
                    HStack(spacing: 12) {
                        calcButton("4", bg: darkGray, fg: .white) { pegarNum("4") }
                        calcButton("5", bg: darkGray, fg: .white) { pegarNum("5") }
                        calcButton("6", bg: darkGray, fg: .white) { pegarNum("6") }
                        calcButton("-", bg: orangeOp, fg: .white) { definirOperacao(-) }
                    }

                    // Linha 4: 1 2 3 +
                    HStack(spacing: 12) {
                        calcButton("1", bg: darkGray, fg: .white) { pegarNum("1") }
                        calcButton("2", bg: darkGray, fg: .white) { pegarNum("2") }
                        calcButton("3", bg: darkGray, fg: .white) { pegarNum("3") }
                        calcButton("+", bg: orangeOp, fg: .white) { definirOperacao(+) }
                    }

                    // Linha 5: 0 (largo)  ,  =
                    HStack(spacing: 12) {
                        Button(action: { pegarNum("0") }) {
                            Text("0")
                                .font(.system(size: 32, weight: .medium))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 72)
                                .background(Capsule().fill(darkGray))
                        }
                        .buttonStyle(.plain)

                        calcButton(",", bg: darkGray, fg: .white) { pegarNum(",") }
                        calcButton("=", bg: orangeOp, fg: .white) { mostrarResposta() }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Botão reutilizável
    private func calcButton(_ title: String, bg: Color, fg: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(fg)
                .frame(maxWidth: .infinity)
                .frame(height: 72)
                .background(Circle().fill(bg))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Lógica (portada do main.py)

    private func limpar() {
        display = "0"
        num1 = 0
        num2 = 0
        currentOp = nil
        waitingForSecond = false
        lastWasEquals = false
    }

    private func pegarDisplay() -> Double {
        let cleaned = display.replacingOccurrences(of: ",", with: ".")
        return Double(cleaned) ?? 0
    }

    private func mostrarDisplay(_ value: Double) {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            display = String(format: "%.0f", value)
        } else {
            var str = String(value)
            if str.hasSuffix(".0") { str = String(str.dropLast(2)) }
            display = str.replacingOccurrences(of: ".", with: ",")
        }
    }

    private func pegarNum(_ digit: String) {
        if lastWasEquals {
            limpar()
        }

        if waitingForSecond {
            display = digit == "," ? "0," : digit
            waitingForSecond = false
            return
        }

        if digit == "," {
            if display.contains(",") { return }
            display += ","
            return
        }

        if display == "0" {
            display = digit
        } else {
            display += digit
        }
    }

    private func definirOperacao(_ op: @escaping (Double, Double) -> Double) {
        if currentOp != nil && !waitingForSecond {
            // encadeia operação
            num2 = pegarDisplay()
            let result = currentOp!(num1, num2)
            mostrarDisplay(result)
            num1 = result
        } else {
            num1 = pegarDisplay()
        }
        currentOp = op
        waitingForSecond = true
        lastWasEquals = false
    }

    private func mostrarResposta() {
        guard let op = currentOp else { return }
        num2 = pegarDisplay()
        let result = op(num1, num2)
        mostrarDisplay(result)
        num1 = result
        waitingForSecond = true
        lastWasEquals = true
    }

    private func numeroNegativo() {
        let current = pegarDisplay()
        mostrarDisplay(current * -1)
    }

    private func porcentagem() {
        var value = pegarDisplay() / 100
        if let op = currentOp, op(2, 3) == 5 || op(2, 3) == -1 {
            // no original: se for + ou - multiplica pelo num1
            value = num1 * value
        }
        mostrarDisplay(value)
    }
}
