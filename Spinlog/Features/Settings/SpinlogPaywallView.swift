import SwiftUI

/// Fenêtre d'incitation à l'abonnement Spinlog Premium (Paywall),
/// affichée au lancement pour les utilisateurs non-premium et accessible depuis les réglages.
struct SpinlogPaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var premiumStore = PremiumStore.shared

    enum SubscriptionPlan {
        case yearly
        case monthly
    }

    @State private var selectedPlan: SubscriptionPlan = .yearly
    @State private var showAllPlans: Bool = false
    @State private var showsAllFeatures: Bool = false
    @State private var showingRestoreAlert: Bool = false

    var body: some View {
        ZStack(alignment: .top) {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // 1. Bannière artistique avec vinyles et pochettes, dans les tons du thème actif
                    PaywallHeaderGraphicView()

                    VStack(spacing: 18) {
                        // 2. Titres d'en-tête
                        VStack(spacing: 6) {
                            Text("Obtenez un accès illimité")
                                .font(.system(size: 27, weight: .bold))
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.center)

                            HStack(spacing: 6) {
                                Text("Essayer Spinlog")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color.appSecondaryText)

                                Text("Premium")
                                    .font(.system(size: 11, weight: .heavy))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Color.spinlogPinkButtonGradient, in: Capsule())
                            }
                        }
                        .padding(.top, 4)

                        // 3. Liste des fonctionnalités
                        VStack(alignment: .leading, spacing: 14) {
                            featureRow(
                                regularPrefix: "Scannez un nombre illimité d'albums et ",
                                boldText: "ajoutez toute votre collection"
                            )
                            featureRow(
                                regularPrefix: "Organisez votre collection avec des ",
                                boldText: "dossiers et des tags"
                            )
                            featureRow(
                                regularPrefix: "Consultez les ",
                                boldText: "statistiques détaillées et tops d'écoute"
                            )
                            featureRow(
                                regularPrefix: "Suivez la cote et la ",
                                boldText: "valeur marchande de vos disques"
                            )

                            if showsAllFeatures {
                                featureRow(
                                    regularPrefix: "Recevez des ",
                                    boldText: "alertes de prix wantlist en direct"
                                )
                                featureRow(
                                    regularPrefix: "Guide de ",
                                    boldText: "rangement physique dans vos meubles"
                                )
                                featureRow(
                                    regularPrefix: "Personnalisez l'ambiance avec les ",
                                    boldText: "8 thèmes de couleurs"
                                )
                            } else {
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                        showsAllFeatures = true
                                    }
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "plus")
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundStyle(Color.spinlogPink)

                                        Text("et 3 fonctionnalités supplémentaires")
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(Color.spinlogPink)
                                    }
                                    .padding(.top, 2)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 22)
                        .padding(.top, 6)

                        // 4. Cartes de réassurance / Preuves sociales
                        HStack(spacing: 12) {
                            VStack(spacing: 5) {
                                HStack(spacing: 4) {
                                    Image(systemName: "laurel.leading")
                                        .font(.system(size: 17, weight: .bold))
                                    Image(systemName: "apple.logo")
                                        .font(.system(size: 14, weight: .bold))
                                    Image(systemName: "laurel.trailing")
                                        .font(.system(size: 17, weight: .bold))
                                }
                                .foregroundStyle(Color.spinlogPink)

                                Text("Sélection Vinyle")
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(Color.appSecondaryText)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .appleMusicGroupedCard(cornerRadius: 16)

                            VStack(spacing: 5) {
                                HStack(spacing: 3) {
                                    ForEach(0..<5) { _ in
                                        Image(systemName: "star.fill")
                                            .font(.system(size: 12))
                                            .foregroundStyle(Color.spinlogPink)
                                    }
                                }

                                Text("4,9 / 5 sur l'App Store")
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(Color.appSecondaryText)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .appleMusicGroupedCard(cornerRadius: 16)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 4)

                        // 5. Plans d'abonnement
                        VStack(spacing: 10) {
                            annualPlanCard

                            if showAllPlans {
                                monthlyPlanCard
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                            }

                            if !showAllPlans {
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                                        showAllPlans = true
                                    }
                                } label: {
                                    Text("Afficher tous les forfaits")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(Color.appSecondaryText)
                                        .padding(.vertical, 6)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 6)

                        // 6. Bouton Continuer principal (CTA)
                        Button {
                            handleContinue()
                        } label: {
                            Text("Continuer")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 54)
                                .background(Color.spinlogPinkButtonGradient, in: Capsule())
                                .shadow(color: Color.spinlogPink.opacity(0.35), radius: 14, y: 6)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 20)
                        .padding(.top, 6)

                        // 7. Mention réassurance & Liens légaux
                        VStack(spacing: 8) {
                            HStack(spacing: 5) {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 9))
                                Text("Paiement sécurisé par Apple. Annulez à tout moment.")
                                    .font(.caption2)
                            }
                            .foregroundStyle(Color.appSecondaryText)

                            HStack(spacing: 14) {
                                Button("Restaurer les achats") {
                                    showingRestoreAlert = true
                                }
                                Text("•").opacity(0.3)
                                Button("Conditions d'utilisation") {}
                                Text("•").opacity(0.3)
                                Button("Confidentialité") {}
                            }
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(Color.appTertiaryText)
                        }
                        .padding(.top, 4)
                        .padding(.bottom, 24)
                    }
                }
            }

            // Bouton Fermer (X) en haut à gauche
            HStack {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.black.opacity(0.35), in: Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .padding(.leading, 18)
                .padding(.top, 14)

                Spacer()
            }
        }
        .alert("Achats restaurés", isPresented: $showingRestoreAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Si vous aviez un abonnement actif, votre accès Premium a été restauré.")
        }
    }

    // MARK: - Carte Annuel

    private var annualPlanCard: some View {
        let isSelected = selectedPlan == .yearly
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                selectedPlan = .yearly
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Annuel")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.primary)

                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("30,00 € / an")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.primary)

                            Text("(2,50 €/mois)")
                                .font(.caption.weight(.regular))
                                .foregroundStyle(Color.appSecondaryText)
                        }
                    }

                    Spacer()

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.spinlogPink : Color.appTertiaryText)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(isSelected ? Color.spinlogPinkBadge : Color(uiColor: .secondarySystemGroupedBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(
                            isSelected ? Color.spinlogPink : Color.primary.opacity(0.08),
                            lineWidth: isSelected ? 2 : 1
                        )
                )

                // Badge "ÉCONOMISEZ 16%"
                Text("ÉCONOMISEZ 16%")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color.spinlogPink, in: Capsule())
                    .offset(x: -16, y: -10)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Carte Mensuel

    private var monthlyPlanCard: some View {
        let isSelected = selectedPlan == .monthly
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                selectedPlan = .monthly
            }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Mensuel")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text("2,99 € / mois")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.spinlogPink : Color.appTertiaryText)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isSelected ? Color.spinlogPinkBadge : Color(uiColor: .secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.spinlogPink : Color.primary.opacity(0.08),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Ligne de fonctionnalité

    private func featureRow(regularPrefix: String, boldText: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(Color.spinlogPink)
                .padding(.top, 2)

            (Text(regularPrefix).font(.subheadline).foregroundStyle(.primary.opacity(0.85))
             + Text(boldText).font(.subheadline.weight(.bold)).foregroundStyle(.primary))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Validation & Achat

    private func handleContinue() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        premiumStore.isPremium = true
        dismiss()
    }
}

// MARK: - Illustration graphique du Header

private struct PaywallHeaderGraphicView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.spinlogPinkDeep, Color.spinlogPink],
                startPoint: .top,
                endPoint: .bottom
            )

            // Composition de vinyles et pochettes, dans les tons du thème actif
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.spinlogPinkDeep.opacity(0.7))
                    .frame(width: 90, height: 90)
                    .rotationEffect(.degrees(-18))
                    .offset(x: -140, y: -20)
                    .opacity(0.7)

                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.black.opacity(0.22))
                    .frame(width: 110, height: 110)
                    .rotationEffect(.degrees(14))
                    .offset(x: 130, y: -15)
                    .opacity(0.8)

                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.spinlogPinkLight)
                    .frame(width: 105, height: 105)
                    .shadow(color: Color.black.opacity(0.35), radius: 10, x: -4, y: 6)
                    .rotationEffect(.degrees(-6))
                    .offset(x: -75, y: -10)

                vinylDiscView(labelColor: Color.spinlogPinkLight, size: 100)
                    .shadow(color: Color.black.opacity(0.4), radius: 8, y: 5)
                    .offset(x: 35, y: -30)

                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.28))
                    .frame(width: 95, height: 95)
                    .shadow(color: Color.black.opacity(0.4), radius: 8, y: 6)
                    .rotationEffect(.degrees(10))
                    .offset(x: 20, y: 55)

                vinylDiscView(labelColor: Color.white.opacity(0.85), size: 110)
                    .shadow(color: Color.black.opacity(0.45), radius: 10, y: 6)
                    .offset(x: 105, y: 25)

                vinylDiscView(labelColor: Color.spinlogPinkDeep.opacity(0.85), size: 95)
                    .shadow(color: Color.black.opacity(0.45), radius: 10, y: 6)
                    .offset(x: -125, y: 40)
            }

            // Fondu vers l'arrière-plan de la page pour une transition sans couture
            VStack {
                Spacer()
                LinearGradient(
                    colors: [Color.clear, Color(uiColor: .systemGroupedBackground)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 60)
            }
        }
        .frame(height: 205)
        .clipShape(PaywallHeaderCurve())
    }

    private func vinylDiscView(labelColor: Color, size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [Color(white: 0.16), Color(white: 0.07), Color(white: 0.13)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: size, height: size)

            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                .frame(width: size * 0.84, height: size * 0.84)
            Circle()
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
                .frame(width: size * 0.70, height: size * 0.70)
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                .frame(width: size * 0.56, height: size * 0.56)

            AngularGradient(
                colors: [Color.clear, Color.white.opacity(0.12), Color.clear, Color.white.opacity(0.12), Color.clear],
                center: .center
            )
            .clipShape(Circle())
            .frame(width: size, height: size)

            Circle()
                .fill(labelColor)
                .frame(width: size * 0.36, height: size * 0.36)

            Circle()
                .fill(Color(red: 0.08, green: 0.08, blue: 0.12))
                .frame(width: size * 0.10, height: size * 0.10)
        }
    }
}

// MARK: - Découpe incurvée de l'en-tête

private struct PaywallHeaderCurve: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: rect.height - 24))
        path.addQuadCurve(
            to: CGPoint(x: 0, y: rect.height - 24),
            control: CGPoint(x: rect.width / 2, y: rect.height + 14)
        )
        path.closeSubpath()
        return path
    }
}
