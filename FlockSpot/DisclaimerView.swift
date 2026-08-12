import SwiftUI

struct DisclaimerView: View {
    @Binding var disclaimerAccepted: Bool
    @State private var isChecked = false
    @State private var showDetails = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Must Read Before Use")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.white)

                        Divider().background(Color.gray)

                        Group {
                            SectionHeader(title: "Purpose")
                            Text("FlockSpot GPS is an independent, community-built tool that helps you identify nearby **ALPR (Automatic License Plate Reader) cameras** and route around them. It is **not affiliated with, endorsed by, or connected to Flock Safety, LLC** or any other surveillance vendor.")
                                .foregroundColor(.white.opacity(0.9))

                            SectionHeader(title: "What We Track")
                            Text("This app displays **all ALPR cameras** reported in OpenStreetMap — not just Flock Safety. This includes cameras operated by:")
                                .foregroundColor(.white.opacity(0.9))
                            VStack(alignment: .leading, spacing: 6) {
                                AlprBrand(text: "Flock Safety")
                                AlprBrand(text: "Motorola / Vigilant Solutions")
                                AlprBrand(text: "Genetec")
                                AlprBrand(text: "ELSAG (Magnetic AutoControl)")
                                AlprBrand(text: "Rekor / Autoplate")
                                AlprBrand(text: "Gtechna / Mediafleet")
                                AlprBrand(text: "PlateSmart")
                                AlprBrand(text: "Any other ALPR vendor")
                            }
                            Text("Camera operators may include **police departments, sheriff's offices, state agencies, toll authorities, private security firms, HOAs, and private property owners**. The map does not distinguish between operator types.")
                                .foregroundColor(.white.opacity(0.9))

                            SectionHeader(title: "Data Sources")
                            Text("Camera locations are sourced from **OpenStreetMap**, a collaborative, open-data project. Locations may be incomplete, outdated, or inaccurate. Many ALPR cameras exist that are **not mapped**. FlockSpot GPS makes no guarantees about data accuracy or completeness.")
                                .foregroundColor(.white.opacity(0.9))
                        }

                        Group {
                            SectionHeader(title: "No Legal Advice")
                            Text("This app is provided for **informational purposes only**. It does not constitute legal advice. Camera presence or absence does not determine the legality of any action. Consult a qualified attorney for legal guidance.")
                                .foregroundColor(.white.opacity(0.9))

                            SectionHeader(title: "Limitation of Liability")
                            Text("By using FlockSpot GPS, you agree that the developers assume **no liability** for any consequences arising from the use or misuse of this application. You are solely responsible for your actions. Use at your own risk.")
                                .foregroundColor(.white.opacity(0.9))
                        }

                        Group {
                            SectionHeader(title: "How We Protect Your Data")
                            VStack(alignment: .leading, spacing: 10) {
                                DataPoint(text: "Location data is processed **on-device** for compass and map features. When you use turn-by-turn navigation, your start and destination coordinates are sent to OpenStreetMap's Valhalla routing service to calculate a camera-safe route.")
                                DataPoint(text: "Camera data is fetched from **OpenStreetMap's public Overpass API** — a free, open data source. No personal data is sent in these requests.")
                                DataPoint(text: "We do **not** collect, store, transmit, or sell any personal information, usage analytics, or identifying data.")
                                DataPoint(text: "Camera data is cached locally on your device for performance. This cache never leaves your device and can be cleared at any time in Settings.")
                                DataPoint(text: "We have **no servers, no databases, and no telemetry**. Your usage is completely private.")
                            }
                        }

                        Group {
                            SectionHeader(title: "Third-Party Services")
                            Text("OpenStreetMap data and Valhalla routing are provided under the **Open Database License (ODbL)**. Map data © OpenStreetMap contributors. Navigation coordinates are sent to Valhalla only when you request a route.")
                                .foregroundColor(.white.opacity(0.9))
                        }
                    }
                    .padding()
                }

                Divider().background(Color.gray)

                VStack(spacing: 16) {
                    Button(action: { showDetails.toggle() }) {
                        Text(showDetails ? "Hide Details" : "Read Full Terms")
                            .foregroundColor(.blue)
                    }

                    HStack(spacing: 12) {
                        Button(action: { isChecked.toggle() }) {
                            Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(isChecked ? .green : .gray)
                                .font(.title2)
                        }

                        Text("I have read and agree to the above terms")
                            .foregroundColor(.white)
                            .font(.subheadline)
                    }

                    Button(action: {
                        disclaimerAccepted = true
                    }) {
                        Text("Continue")
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(isChecked ? Color.blue : Color.gray)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    .disabled(!isChecked)
                }
                .padding()
            }
        }
    }
}

struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.headline)
            .foregroundColor(.green)
    }
}

struct DataPoint: View {
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lock.shield")
                .foregroundColor(.green)
                .font(.caption)
                .padding(.top, 2)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.9))
        }
    }
}

struct AlprBrand: View {
    let text: String
    var body: some View {
        HStack(spacing: 6) {
            Text("•")
                .foregroundColor(.green)
            Text(text)
                .font(.caption)
                .foregroundColor(.white.opacity(0.8))
        }
        .padding(.leading, 8)
    }
}

struct DisclaimerView_Previews: PreviewProvider {
    static var previews: some View {
        DisclaimerView(disclaimerAccepted: .constant(false))
    }
}
