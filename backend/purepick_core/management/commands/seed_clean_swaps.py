from django.core.management.base import BaseCommand
from purepick_core.models import CleanProduct

class Command(BaseCommand):
    help = 'Seeds the database with curated clean swaps and barcode data'

    def handle(self, *args, **options):
        # 1. CURATED CLEAN SWAPS (Massive Expansion)
        products = [
            # Cleansers
            {'brand': 'CeraVe', 'name': 'Hydrating Facial Cleanser', 'category': 'cleanser', 'score': 98},
            {'brand': 'La Roche-Posay', 'name': 'Toleriane Hydrating Gentle Cleanser', 'category': 'cleanser', 'score': 96},
            {'brand': 'Cetaphil', 'name': 'Gentle Skin Cleanser', 'category': 'cleanser', 'score': 94},
            {'brand': 'Vanicream', 'name': 'Gentle Facial Cleanser', 'category': 'cleanser', 'score': 100},
            {'brand': 'Youth to the People', 'name': 'Superfood Antioxidant Cleanser', 'category': 'cleanser', 'score': 95},
            {'brand': 'Fresh', 'name': 'Soy Face Cleanser', 'category': 'cleanser', 'score': 93},

            # Moisturizers
            {'brand': 'The Ordinary', 'name': 'Natural Moisturizing Factors + HA', 'category': 'moisturizer', 'score': 99},
            {'brand': 'Neutrogena', 'name': 'Hydro Boost Water Gel', 'category': 'moisturizer', 'score': 92},
            {'brand': 'Kiehl\'s', 'name': 'Ultra Facial Cream', 'category': 'moisturizer', 'score': 95},
            {'brand': 'Drunk Elephant', 'name': 'Lala Retro Whipped Cream', 'category': 'moisturizer', 'score': 91},
            {'brand': 'Tatcha', 'name': 'The Dewy Skin Cream', 'category': 'moisturizer', 'score': 90},
            {'brand': 'First Aid Beauty', 'name': 'Ultra Repair Cream', 'category': 'moisturizer', 'score': 97},

            # Sunscreens
            {'brand': 'EltaMD', 'name': 'UV Clear Broad-Spectrum SPF 46', 'category': 'sunscreen', 'score': 97},
            {'brand': 'Supergoop!', 'name': 'Unseen Sunscreen SPF 40', 'category': 'sunscreen', 'score': 94},
            {'brand': 'Biore', 'name': 'Aqua Rich Watery Essence SPF 50+', 'category': 'sunscreen', 'score': 93},
            {'brand': 'La Roche-Posay', 'name': 'Anthelios Melt-in Milk Sunscreen', 'category': 'sunscreen', 'score': 95},
            {'brand': 'Australian Gold', 'name': 'Botanical Tinted Face Sunscreen', 'category': 'sunscreen', 'score': 98},

            # Shampoos
            {'brand': 'Native', 'name': 'Cucumber \u0026 Mint Volumizing Shampoo', 'category': 'shampoo', 'score': 98},
            {'brand': 'SheaMoisture', 'name': 'Raw Shea Butter Moisture Retention Shampoo', 'category': 'shampoo', 'score': 95},
            {'brand': 'Briogeo', 'name': 'Be Gentle, Be Kind Banana + Coconut Shampoo', 'category': 'shampoo', 'score': 99},
            {'brand': 'Love Beauty and Planet', 'name': 'Coconut Oil \u0026 Ylang Ylang Shampoo', 'category': 'shampoo', 'score': 92},
            {'brand': 'Aveeno', 'name': 'Apple Cider Vinegar Blend Shampoo', 'category': 'shampoo', 'score': 94},

            # Serums
            {'brand': 'The Ordinary', 'name': 'Niacinamide 10% + Zinc 1%', 'category': 'serum', 'score': 100},
            {'brand': 'SkinCeuticals', 'name': 'C E Ferulic', 'category': 'serum', 'score': 97},
            {'brand': 'Paula\'s Choice', 'name': 'Skin Perfecting 2% BHA Liquid Exfoliant', 'category': 'serum', 'score': 96},
            {'brand': 'Estée Lauder', 'name': 'Advanced Night Repair', 'category': 'serum', 'score': 91},
            {'brand': 'Glossier', 'name': 'Super Pure Niacinamide Serum', 'category': 'serum', 'score': 98},

            # Conditioners
            {'brand': 'Pureology', 'name': 'Hydrate Conditioner', 'category': 'conditioner', 'score': 96},
            {'brand': 'Olaplex', 'name': 'No. 5 Bond Maintenance Conditioner', 'category': 'conditioner', 'score': 94},
            {'brand': 'Maui Moisture', 'name': 'Heal \u0026 Hydrate + Shea Butter Conditioner', 'category': 'conditioner', 'score': 97},

            # Body Washes
            {'brand': 'Method', 'name': 'Body Wash Pure Peace', 'category': 'body_wash', 'score': 95},
            {'brand': 'Dove', 'name': 'Deep Moisture Body Wash', 'category': 'body_wash', 'score': 91},
            {'brand': 'Necessaire', 'name': 'The Body Wash', 'category': 'body_wash', 'score': 100},
        ]

        for p in products:
            CleanProduct.objects.get_or_create(
                brand=p['brand'],
                name=p['name'],
                defaults={'category': p['category'], 'safety_score': p['score']}
            )

        self.stdout.write(self.style.SUCCESS(f'Successfully seeded {len(products)} clean products!'))
